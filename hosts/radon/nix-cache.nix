{config, ...}: let
  cachePort = 5000;
in {
  age.secrets.nix-cache-private-key.file = ../../secrets/nix-cache-private-key.age;

  services.nix-serve = {
    enable = true;
    bindAddress = "0.0.0.0";
    port = cachePort;
    secretKeyFile = config.age.secrets.nix-cache-private-key.path;
  };

  # Keep the cache private to hosts connected through Tailscale.
  networking.firewall.interfaces.tailscale0.allowedTCPPorts = [cachePort];
}
