{pkgs, ...}: {
  imports = [
    ./gnome
    ./flatpak.nix
    ./korean.nix
    ./tailscale-bookmarks.nix
  ];
  home-manager.sharedModules = [../../home/desktop.nix];

  environment.systemPackages = [pkgs.proton-vpn];
}
