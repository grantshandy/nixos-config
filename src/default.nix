{pkgs, ...}: {
  imports = [
    ./gnome
    # ./flatpak.nix
  ];

  home-manager.sharedModules = [
    ./firefox
    ./zed

    ./beeper.nix
    ./tools.nix
  ];

  environment.systemPackages = [
    pkgs.proton-vpn
    # pkgs.libreoffice
  ];

  # virtualisation.docker.enable = true;
  # users.users.grant.extraGroups = ["docker"];

  # services.ollama = {
  # enable = true;
  # package = pkgs.ollama-rocm;
  # };

  # services.gnome.core-developer-tools.enable = true;

  # services.openssh = {
  #   enable = true;
  #   ports = [4321];
  # };

  # programs.steam.enable = true;
}
