{
  config,
  lib,
  pkgs,
  ...
}: let
  thisHostName = config.networking.hostName;
  thisHost =
    config.network.hosts.${thisHostName}
    or (throw "host '${thisHostName}' is missing from network.hosts");

  peers =
    if thisHost.cache.pull && thisHost.tailscale.enable
    then
      config.network.hosts
      |> lib.filterAttrs (name: host: name != thisHostName && host.cache.push)
      |> lib.mapAttrsToList (name: host: {inherit name host;})
      |> lib.sort (a: b: a.host.cache.priority < b.host.cache.priority)
    else [];

  proxyPort = 6000;
  proxyPathFor = peer: "${toString peer.host.cache.priority}-${peer.name}";

  peerSubstituters =
    map (
      peer: "http://127.0.0.1:${toString proxyPort}/${proxyPathFor peer}?priority=${toString peer.host.cache.priority}"
    )
    peers;

  proxyLocations =
    builtins.listToAttrs (lib.concatMap (peer: [
        {
          name = "= /${proxyPathFor peer}/nix-cache-info";
          value = {
            alias = pkgs.writeText "nix-cache-info-${peer.name}" ''
              StoreDir: /nix/store
              WantMassQuery: 1
              Priority: ${toString peer.host.cache.priority}
            '';
            extraConfig = "default_type text/plain;";
          };
        }
        {
          name = "/${proxyPathFor peer}/";
          value = {
            # The trailing slash strips the identifying local proxy prefix.
            proxyPass = "http://${peer.name}:${toString peer.host.cache.port}/";
            extraConfig = ''
              proxy_connect_timeout 500ms;
              proxy_read_timeout 5m;
              proxy_buffering off;
              proxy_request_buffering off;
              proxy_intercept_errors on;
              error_page 500 502 503 504 = @cache_miss;
            '';
          };
        }
      ])
      peers)
    // {"@cache_miss".return = 404;};

  proxyVirtualHost = {
    listen = [
      {
        addr = "127.0.0.1";
        port = proxyPort;
      }
    ];
    extraConfig = ''
      access_log off;
      error_log /dev/null crit;
    '';
    locations = proxyLocations;
  };

  cachePublicKey =
    builtins.readFile ../../secrets/nix-cache-public-key
    |> lib.removeSuffix "\n";
in {
  age = lib.mkIf thisHost.cache.push {
    identityPaths = ["/etc/ssh/ssh_host_ed25519_key"];
    secrets.nix-cache-private-key.file = ../../secrets/nix-cache-private-key.age;
  };

  services.nix-serve = lib.mkIf thisHost.cache.push {
    enable = true;
    bindAddress = "0.0.0.0";
    port = thisHost.cache.port;
    secretKeyFile = config.age.secrets.nix-cache-private-key.path;
  };

  systemd.services.nix-serve.restartTriggers =
    lib.mkIf thisHost.cache.push [../../secrets/nix-cache-private-key.age];

  networking.firewall.interfaces.tailscale0.allowedTCPPorts =
    lib.mkIf thisHost.cache.push [thisHost.cache.port];

  services.nginx = lib.mkIf (peers != []) {
    enable = true;
    virtualHosts.nix-cache-mesh = proxyVirtualHost;
  };

  # The peer proxies do not write file logs, so Nginx's default logrotate
  # entry would only inspect an unused /var/log/nginx glob.
  services.logrotate.settings.nginx.enable = lib.mkIf (peers != []) false;

  nix.settings = {
    substituters = lib.mkBefore peerSubstituters;
    trusted-public-keys = lib.mkBefore [cachePublicKey];

    # Peer proxy failures become immediate cache misses. Keep fallback enabled
    # for the rare case where a peer disappears during an active NAR transfer.
    fallback = true;
  };

  assertions = [
    {
      assertion = !(thisHost.cache.pull || thisHost.cache.push) || thisHost.tailscale.enable;
      message = "A host pulling from or pushing a Nix cache must have Tailscale enabled.";
    }
  ];
}
