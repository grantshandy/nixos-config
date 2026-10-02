{config, ...}: {
  imports = [./firefox ./zed ./beeper.nix ./uofu-vpn.nix];

  services.uofu-vpn.enable = true;

  desktop.favoriteApps = [
    "org.gnome.Nautilus.desktop"
    "org.gnome.Ptyxis.desktop"
  ];

  dconf.settings."org/gnome/shell".favorite-apps = config.desktop.favoriteApps;
}
