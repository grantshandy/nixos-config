{...}: {
  imports = [./hardware-configuration.nix ../../modules/nixos/bootloader-systemd.nix ../../modules/nixos/desktop];

  boot.binfmt.emulatedSystems = ["aarch64-linux"];
}
