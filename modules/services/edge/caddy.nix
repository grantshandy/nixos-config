# The public entry point for the whole homelab.
#
# Nothing here names a host or a service. Routing, the upstream to use, and the
# authentication policy to apply all come from the service registry, so adding a
# public service means declaring it in its own file and nothing else. Previously
# this file hardcoded radon's proxy address, special-cased Cockpit by name, and
# carried a literal list of the paths that needed protecting.
{
  config,
  lib,
  ...
}: let
  dns = config.fleet.identity.homelab.dns;
  edgeHost = config.fleet.edgeHost;

  sessionAuth = ''
    forward_auth 127.0.0.1:9091 {
      uri /api/authz/forward-auth
      header_up X-Forwarded-Proto https
      copy_headers Remote-User Remote-Groups Remote-Email Remote-Name
    }
  '';

  backendAuth = ''
    forward_auth 127.0.0.1:9091 {
      uri /api/authz/forward-auth
      header_up X-Forwarded-Proto https
      # API credentials belong to the backend, not the authorization subrequest.
      # These changes affect only the cloned forward-auth request.
      header_up -Authorization
      header_up -X-Api-Key
      header_up X-Forwarded-URI {http.request.uri.path}
      copy_headers Remote-User Remote-Groups Remote-Email Remote-Name
    }
  '';

  authFor = service:
    {
      none = "";
      session = sessionAuth;
      backend = backendAuth;
    }
    .${
      service.auth
    };

  upstreamFor = service: let
    tailnetName = "${service.host}.ts.${dns}";
    proxyPort = config.fleet.hosts.${service.host}.proxyPort;
  in
    if service.upstream == "direct"
    then "${tailnetName}:${toString service.port}"
    else "http://${tailnetName}:${toString proxyPort}";

  # The edge only fronts services that live on *other* machines; its own
  # services publish their virtual hosts alongside their implementations.
  remote =
    config.fleet.services
    |> lib.filterAttrs (_: service: service.public && service.host != edgeHost);

  subdomainVirtualHosts =
    remote
    |> lib.filterAttrs (_: service: service.subdomain != null)
    |> lib.mapAttrs' (_: service:
      lib.nameValuePair service.fqdn {
        extraConfig = ''
          ${authFor service}
          reverse_proxy ${upstreamFor service}
        '';
      });

  # Apex-domain services share one virtual host, so they are grouped by owning
  # host and policy: each group contributes one path matcher and one handler.
  # The groups are disjoint by construction, and stricter policies come first.
  apexServices = remote |> lib.attrValues |> lib.filter (service: service.apexPaths != []);

  apexGroups =
    ["backend" "session" "none"]
    |> lib.concatMap (policy:
      apexServices
      |> lib.filter (service: service.auth == policy)
      |> lib.groupBy (service: service.host)
      |> lib.mapAttrsToList (host: services: {
        inherit policy host;
        paths = services |> lib.concatMap (service: service.apexPaths) |> lib.unique;
        upstream = upstreamFor (lib.head services);
        auth = authFor (lib.head services);
      }));

  apexHandlers =
    apexGroups
    |> map (group: ''
      @${group.policy}Apex${group.host} path ${lib.concatStringsSep " " group.paths}
      handle @${group.policy}Apex${group.host} {
        ${group.auth}
        reverse_proxy ${group.upstream}
      }
    '')
    |> lib.concatStringsSep "\n";
in {
  fleet.aspects.edge-caddy.tags = ["edge"];

  flake.modules.nixos.edge-caddy = {config, ...}: {
    age.secrets.duckdns-token.file = ../../../secrets/duckdns-token.age;

    services.duckdns = {
      enable = true;
      domains = [(lib.head (lib.splitString "." dns))];
      tokenFile = config.age.secrets.duckdns-token.path;
    };

    services.caddy = {
      enable = true;
      globalConfig = ''
        auto_https disable_redirects
        acme_ca https://acme-v02.api.letsencrypt.org/directory
        email ${config.identity.git.email}
        # A reload stops the old HTTP servers and waits for their connections to
        # drain. A live video stream never ends, so without a bound that wait is
        # forever: it holds the admin API's lock, every `caddy reload` hangs
        # until systemd kills it, and the new config silently never loads.
        grace_period 10s
      '';
      virtualHosts =
        subdomainVirtualHosts
        // {
          ${dns}.extraConfig = lib.mkBefore apexHandlers;
        };
    };

    networking.firewall.allowedTCPPorts = [443];
  };
}
