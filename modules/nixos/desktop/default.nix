{pkgs, ...}: {
  imports = [
    ./gnome
    ./flatpak.nix
    ./korean.nix
  ];
  home-manager.sharedModules = [
    ../../home/desktop.nix
  ];

  services.slskd-notify.client.enable = true;

  environment.systemPackages = [pkgs.proton-vpn];
}
