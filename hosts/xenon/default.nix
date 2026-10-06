{...}: {
  imports = [
    ./hardware-configuration.nix
    ../../modules/nixos/bootloader-systemd.nix
    ../../modules/nixos/desktop
    # ../../modules/nixos/soulseek.nix
  ];

  # networking.networkmanager.wifi.backend = "iwd";
  # networking.networkmanager.wifi.powersave = false;

  boot.binfmt.emulatedSystems = ["aarch64-linux"];
}
