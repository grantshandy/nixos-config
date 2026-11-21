{modulesPath, ...}: {
  imports = [
    (modulesPath + "/profiles/minimal.nix")
    ./hardware-configuration.nix
    ../../modules/nixos/bootloader-systemd.nix
    ./lean.nix
    ./edge.nix
    ./auth.nix
    ./directory.nix
    ./headscale.nix
    ./blocky.nix
    ./monitoring.nix
  ];

  networking.useDHCP = true;

  nix = {
    gc = {
      automatic = true;
      dates = "weekly";
      options = "--delete-older-than 7d";
    };
    settings = {
      min-free = 1024 * 1024 * 1024;
      max-free = 2 * 1024 * 1024 * 1024;
    };
  };

  services.openssh.settings.PasswordAuthentication = false;

  # The base user has no declarative password. Keep the key-authenticated user
  # capable of administering this headless machine after its first boot.
  security.sudo.wheelNeedsPassword = false;
}
