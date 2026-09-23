{config, ...}: {
  imports = [./firefox ./zed ./beeper.nix];

  desktop.favoriteApps = [
    "org.gnome.Nautilus.desktop"
    "org.gnome.Ptyxis.desktop"
  ];

  dconf.settings."org/gnome/shell".favorite-apps = config.desktop.favoriteApps;
}
