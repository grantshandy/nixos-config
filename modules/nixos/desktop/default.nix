{pkgs, ...}: {
  imports = [
    ./gnome
    ./flatpak.nix
    ./korean.nix
  ];
  home-manager.sharedModules = [
    ../../home/desktop.nix
  ];

  environment.systemPackages = [pkgs.proton-vpn];
}
