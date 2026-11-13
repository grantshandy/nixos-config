{
  config,
  lib,
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

  peerSubstituters =
    map (
      peer: "http://${peer.name}:${toString peer.host.cache.port}?priority=${toString peer.host.cache.priority}"
    )
    peers;

  cachePublicKey =
    builtins.readFile ../../secrets/nix-cache-public-key
    |> lib.removeSuffix "\n";
in {
  age = {
    identityPaths = [
      "/etc/ssh/ssh_host_ed25519_key"
      "/home/${config.identity.user.name}/.ssh/id_ed25519"
    ];
    secrets.nix-cache-private-key.file = ../../secrets/nix-cache-private-key.age;
  };

  services.nix-serve = lib.mkIf thisHost.cache.enable {
    enable = true;
    bindAddress = "0.0.0.0";
    port = thisHost.cache.port;
    secretKeyFile = config.age.secrets.nix-cache-private-key.path;
  };

  networking.firewall.interfaces.tailscale0.allowedTCPPorts =
    lib.mkIf thisHost.cache.enable [thisHost.cache.port];

  nix.settings = {
    substituters = lib.mkBefore peerSubstituters;
    trusted-public-keys = lib.mkBefore [cachePublicKey];

    # An unavailable peer should add only a short delay before Nix tries the
    # next peer or cache.nixos.org.
    connect-timeout = 2;
    fallback = true;
  };

  assertions = [
    {
      assertion = !thisHost.cache.enable || thisHost.tailscale.enable;
      message = "A host serving the Nix cache must have Tailscale enabled.";
    }
  ];
}
