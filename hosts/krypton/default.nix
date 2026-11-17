{config, ...}: {
  imports = [
    ./hardware-configuration.nix
    ../../modules/nixos/bootloader-systemd.nix
  ];

  networking.useDHCP = true;

  services.openssh.settings.PasswordAuthentication = false;

  # The base user has no declarative password. Keep the key-authenticated user
  # capable of administering this headless machine after its first boot.
  security.sudo.wheelNeedsPassword = false;

  nix.settings.trusted-users = [config.identity.user.name];
}
