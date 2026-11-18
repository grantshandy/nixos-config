{modulesPath, ...}: {
  imports = [
    (modulesPath + "/profiles/minimal.nix")
    ../../modules/nixos/profiles/kiosk.nix
    ./hardware-configuration.nix
    ../../modules/nixos/bootloader-systemd.nix
    ./virtual-machine-kiosk.nix
  ];

  networking.useDHCP = true;

  services.openssh.settings.PasswordAuthentication = false;

  # The base user has no declarative password. Keep the key-authenticated user
  # capable of administering this headless machine after its first boot.
  security.sudo.wheelNeedsPassword = false;
}
