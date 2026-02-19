{
  pkgs,
  lib,
  userConfig,
  ...
}: {
  imports = [
    ./gnome
    ./firefox
    ./zed
    ./beeper.nix
    ./flatpak.nix
  ];

  environment.systemPackages = with pkgs; [
    eyedropper
  ];

  # services.openssh = {
  #   enable = true;
  #   ports = [4321];
  # };

  # programs.steam.enable = true;
}
