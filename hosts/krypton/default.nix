{config, ...}: {
  imports = [
    ./hardware-configuration.nix
    ../../modules/nixos/bootloader-systemd.nix
  ];

  networking.useDHCP = true;

  users.users.${config.identity.user.name}.openssh.authorizedKeys.keys = config.identity.ssh.userKeys;
  services.openssh.settings.PasswordAuthentication = false;

  # The base user has no declarative password. Keep the key-authenticated user
  # capable of administering this headless machine after its first boot.
  security.sudo.wheelNeedsPassword = false;

  nix.settings.trusted-users = [config.identity.user.name];
}
