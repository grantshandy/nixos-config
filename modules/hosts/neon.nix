# Lenovo IdeaPad 5 15ARE05. Minimal console-only fleet member.
{
  fleet.hosts.neon = {
    system = "x86_64-linux";
    tags = ["minimal"];
    homeManager.enable = false;
    remoteDevelopment.enable = false;

    ssh = {
      enable = true;
      targetHost = "192.168.86.27";
      port = 22;
    };
  };

  flake.modules.nixos.neon = {
    config,
    lib,
    modulesPath,
    ...
  }: {
    imports = [
      (modulesPath + "/profiles/minimal.nix")
      ./_hardware/neon.nix
    ];

    # Preserve the compatibility baseline of the existing NixOS installation.
    configuration.stateVersion = lib.mkForce "23.11";

    hardware.enableRedistributableFirmware = true;
    boot.loader.systemd-boot.configurationLimit = lib.mkForce 5;

    networking = {
      useDHCP = true;
      wireless = {
        enable = true;
        networks."SummerHill_NET".pskRaw = "dca38956c6dbd03a98a8cdc48304b2566ab3b24161c6e47767c63de808c6d674";
      };
    };

    users.users."${config.identity.user.name}".initialHashedPassword = "$y$j9T$LnKKbq63auLUVPMbeh0W6/$fEieJOkpEGUvHzqUZjmQs.l1jTgDi6Uz0RYFlVurmN4";

    services.openssh.settings.PasswordAuthentication = false;
    security.sudo.wheelNeedsPassword = false;
  };
}
