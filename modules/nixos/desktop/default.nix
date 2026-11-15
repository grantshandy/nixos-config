{pkgs, ...}: {
  imports = [
    ./gnome
    ./flatpak.nix
    ./korean.nix
    ./tailscale-bookmarks.nix
  ];
  home-manager.sharedModules = [../../home/desktop.nix];

  my.slskdNotify.client.enable = true;

  environment.systemPackages = [pkgs.proton-vpn];
}
