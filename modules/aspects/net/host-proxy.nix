# The local reverse proxy that service hosts put in front of their backends.
#
# The edge terminates TLS and then talks to exactly one port per machine; this
# module generates that machine's routing table from the registry. It names no
# host and no service: which machine gets a proxy follows from `proxyPort`, and
# what it routes follows from `localProxy.port`. Previously each endpoint file
# hand-wrote a near-identical `handle`/`redir` pair against an untyped
# `radonCaddyHost` argument.
{
  config,
  lib,
  ...
}: let
  fleet = config.fleet;
  dns = fleet.identity.homelab.dns;

  proxiedHosts =
    fleet.hosts
    |> lib.filterAttrs (_: host: host.proxyPort != null)
    |> lib.attrNames;

  # `/` needs no matcher, and wrapping it in `handle /*` would only add a layer
  # that makes the rendered Caddyfile harder to read.
  backend = service: "reverse_proxy 127.0.0.1:${toString service.localProxy.port}";

  routeFor = service:
    if service.path == "/"
    then backend service
    else ''
      handle ${service.basePath} {
        redir * ${service.path} 308
      }
      ${service.localProxy.extraConfig}
      handle ${service.path}* {
        ${backend service}
      }
    '';

  # Several apex-path services share one virtual host, so each service emits
  # (address, directives) pairs that are grouped afterwards. A service's extra
  # apex redirects belong on the apex address even when the service itself is
  # reached through a subdomain, which is why this is not a plain `groupBy` over
  # the service's own fqdn. The resulting groups are path-disjoint.
  blocksFor = proxyPort: service: let
    address = fqdn: "http://${fqdn}:${toString proxyPort}";
  in
    lib.optional (service.redirectPaths != []) {
      address = address dns;
      text =
        service.redirectPaths
        |> map (path: "redir ${path} ${service.url} 308")
        |> lib.concatStringsSep "\n";
    }
    ++ [
      {
        address = address service.fqdn;
        text = routeFor service;
      }
    ];

  virtualHostsFor = hostName: let
    proxyPort = fleet.hosts.${hostName}.proxyPort;
  in
    fleet.services
    |> lib.attrValues
    |> lib.filter (service: service.public && service.host == hostName && service.localProxy.port != null)
    |> lib.concatMap (blocksFor proxyPort)
    |> lib.groupBy (block: block.address)
    |> lib.mapAttrs (_: blocks: {
      extraConfig = blocks |> map (block: block.text) |> lib.concatStringsSep "\n";
    });
in {
  fleet.aspects.host-proxy.hosts = proxiedHosts;

  flake.modules.nixos.host-proxy = {config, ...}: {
    services.caddy = {
      enable = true;
      # See the identical note on the edge proxy: an unbounded drain lets one
      # long-lived stream wedge the admin API and break every future reload.
      globalConfig = "grace_period 10s";
      virtualHosts = virtualHostsFor config.networking.hostName;
    };
  };
}
