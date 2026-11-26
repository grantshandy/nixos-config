# Tailnet membership, mDNS, and resolver configuration.
#
# Which machine serves tailnet DNS used to be the literal `network.hosts.krypton`
# inside the module; it is now whichever host carries the "tailnet-dns" tag,
# resolved once here.
{
  config,
  lib,
  ...
}: let
  dnsHosts =
    config.fleet.hosts
    |> lib.filterAttrs (_: host: lib.elem "tailnet-dns" host.tags)
    |> lib.attrNames;

  dnsHost =
    if lib.length dnsHosts == 1
    then lib.head dnsHosts
    else throw "Exactly one host must be tagged \"tailnet-dns\", found: ${lib.concatStringsSep ", " dnsHosts}.";
in {
  options.fleet.tailnetDnsHost = lib.mkOption {
    type = lib.types.str;
    readOnly = true;
    description = "Host name of the machine tagged \"tailnet-dns\".";
  };

  config = {
    fleet.tailnetDnsHost = dnsHost;
    fleet.aspects.network-base.default = true;

    flake.modules.nixos.network-base =
      ({
          hosts,
          tailnetDnsHost,
        }: {
          config,
          lib,
          ...
        }: let
          hostName = config.networking.hostName;
          self =
            hosts.${hostName}
    or (throw "host '${hostName}' is missing from the fleet registry");
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
              "--accept-dns=true"
            ];

            extraSetFlags = lib.mkDefault [
              "--accept-dns=true"
            ];
          };

          networking.firewall = {
            allowedTCPPorts = lib.mkIf self.ssh.enable [self.ssh.port];
            trustedInterfaces = lib.mkIf self.tailscale.enable ["tailscale0"];
          };
        }) {
        hosts = config.fleet.hosts;
        tailnetDnsHost = config.fleet.hosts.${config.fleet.tailnetDnsHost};
      };
  };
}
