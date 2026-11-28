# Lenovo IdeaPad 5 15ARE05. Minimal console-only fleet member.
{
  fleet.hosts.neon = {
    system = "x86_64-linux";
    tags = ["minimal"];

    ssh = {
      enable = true;
      port = 22;
    };
    tailscale.enable = true;

    buildCluster.cache.provide = {
      enable = true;
      priority = 15;
    };
  };

  flake.modules.nixos.neon = {modulesPath, ...}: {
    imports = [
      (modulesPath + "/profiles/minimal.nix")
      ./_hardware/neon.nix
    ];

    hardware.enableRedistributableFirmware = true;

    networking = {
      useDHCP = true;
      wireless = {
        enable = true;
        networks."SummerHill_NET".pskRaw = "dca38956c6dbd03a98a8cdc48304b2566ab3b24161c6e47767c63de808c6d674";
      };
    };

    services.openssh.settings.PasswordAuthentication = false;
    security.sudo.wheelNeedsPassword = false;
  };
}
