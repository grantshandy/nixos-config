{...}: {
  imports = [
    ./hardware-configuration.nix
    ../../modules/nixos/bootloader-systemd.nix
    ../../modules/nixos/desktop
    ../../modules/nixos/navidrome.nix
    ../../modules/nixos/soulseek.nix
  ];

  programs.steam.enable = true;

  # networking.networkmanager.wifi.backend = "iwd";
  # networking.networkmanager.wifi.powersave = false;
  boot.binfmt.emulatedSystems = ["aarch64-linux"];
}
