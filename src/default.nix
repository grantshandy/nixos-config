{pkgs, ...}: {
  imports = [
    ./gnome
    ./flatpak.nix
  ];

  home-manager.sharedModules = [
    ./firefox
    ./zed

    ./beeper.nix
    ./tools.nix
  ];

  environment.systemPackages = with pkgs; [
    protonvpn-gui
  ];

  # services.gnome.core-developer-tools.enable = true;

  # services.openssh = {
  #   enable = true;
  #   ports = [4321];
  # };

  # programs.steam.enable = true;
}
