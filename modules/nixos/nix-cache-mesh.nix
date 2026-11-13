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
    config.network.hosts
    |> lib.filterAttrs (name: host: name != thisHostName && host.cache.enable)
    |> lib.mapAttrsToList (name: host: {inherit name host;})
    |> lib.sort (a: b: a.host.cache.priority < b.host.cache.priority);

  proxyPortFor = peer: 6000 + peer.host.cache.priority;

  peerSubstituters =
    map (
      peer: "http://127.0.0.1:${toString (proxyPortFor peer)}?priority=${toString peer.host.cache.priority}"
    )
    peers;

  proxyVirtualHosts = builtins.listToAttrs (map (peer: {
      name = "nix-cache-${peer.name}";
      value = {
        listen = [
          {
            addr = "127.0.0.1";
            port = proxyPortFor peer;
          }
        ];
        extraConfig = ''
          access_log off;
          error_log /dev/null crit;
        '';
        locations = {
          "= /nix-cache-info" = {
            alias = pkgs.writeText "nix-cache-info-${peer.name}" ''
              StoreDir: /nix/store
              WantMassQuery: 1
              Priority: ${toString peer.host.cache.priority}
            '';
            extraConfig = "default_type text/plain;";
          };
          "/" = {
            proxyPass = "http://${peer.name}:${toString peer.host.cache.port}";
            extraConfig = ''
              proxy_connect_timeout 500ms;
              proxy_read_timeout 5m;
              proxy_buffering off;
              proxy_request_buffering off;
              proxy_intercept_errors on;
              error_page 500 502 503 504 = @cache_miss;
            '';
          };
          "@cache_miss".return = 404;
        };
      };
    })
    peers);

  cachePublicKey =
    builtins.readFile ../../secrets/nix-cache-public-key
    |> lib.removeSuffix "\n";
in {
  age = {
    identityPaths = ["/etc/ssh/ssh_host_ed25519_key"];
    secrets.nix-cache-private-key.file = ../../secrets/nix-cache-private-key.age;
  };

  services.nix-serve = lib.mkIf thisHost.cache.enable {
    enable = true;
    bindAddress = "0.0.0.0";
    port = thisHost.cache.port;
    secretKeyFile = config.age.secrets.nix-cache-private-key.path;
  };

  systemd.services.nix-serve.restartTriggers =
    lib.mkIf thisHost.cache.enable [../../secrets/nix-cache-private-key.age];

  networking.firewall.interfaces.tailscale0.allowedTCPPorts =
    lib.mkIf thisHost.cache.enable [thisHost.cache.port];

  services.nginx = {
    enable = true;
    virtualHosts = proxyVirtualHosts;
  };

  nix.settings = {
    substituters = lib.mkBefore peerSubstituters;
    trusted-public-keys = lib.mkBefore [cachePublicKey];

    # Peer proxy failures become immediate cache misses. Keep fallback enabled
    # for the rare case where a peer disappears during an active NAR transfer.
    fallback = true;
  };

  assertions = [
    {
      assertion = !thisHost.cache.enable || thisHost.tailscale.enable;
      message = "A host serving the Nix cache must have Tailscale enabled.";
    }
  ];
}
