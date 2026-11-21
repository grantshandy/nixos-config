{
  config,
  lib,
  ...
}: let
  hostName = config.networking.hostName;
  self =
    config.network.hosts.${hostName}
    or (throw "host '${hostName}' is missing from network.hosts");
  tailnetDnsHost = config.network.hosts.krypton;
  acceptTailnetDns = self.tailscale.enable && hostName != "krypton";
in {
  assertions = [
    {
      assertion = !self.tailscale.enable || tailnetDnsHost.tailscale.ipv4 != null;
      message = "The tailnet DNS host must have a stable Tailscale IPv4 address.";
    }
  ];

  services.avahi = {
    enable = true;
    nssmdns4 = true;
    openFirewall = true;
    publish = {
      enable = true;
      addresses = true;
      workstation = true;
    };
  };

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
      "--accept-dns=${lib.boolToString acceptTailnetDns}"
    ];

    extraSetFlags = lib.mkDefault [
      "--accept-dns=${lib.boolToString acceptTailnetDns}"
    ];
  };

  networking.firewall = {
    allowedTCPPorts = lib.mkIf self.ssh.enable [self.ssh.port];
    trustedInterfaces = lib.mkIf self.tailscale.enable ["tailscale0"];
  };
}
