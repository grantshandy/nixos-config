{
  config,
  lib,
  ...
}: let
  self =
    config.network.hosts.${config.networking.hostName}
    or (throw "host '${config.networking.hostName}' is missing from network.hosts");
in {
  services.openssh = lib.mkIf self.ssh.enable {
    enable = lib.mkDefault true;
    ports = lib.mkDefault [self.ssh.port];
    settings.PasswordAuthentication = lib.mkDefault true;
  };

  services.tailscale = lib.mkIf self.tailscale.enable {
    enable = lib.mkDefault true;
    openFirewall = lib.mkDefault true;
    extraUpFlags = lib.mkDefault [
      "--login-server=https://${config.identity.homelab.dns}"
      "--accept-dns=false"
    ];
  };

  networking.firewall = {
    allowedTCPPorts = lib.mkIf self.ssh.enable [self.ssh.port];
    trustedInterfaces = lib.mkIf self.tailscale.enable ["tailscale0"];
  };
}
