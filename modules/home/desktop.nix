{config, ...}: {
  imports = [
    ./zed
    ./beeper.nix
    ./globalprotect-vpn.nix
    ./gitlab-runner-vpn.nix
  ];

  services.globalprotect-vpn = {
    enable = true;
    name = "University of Utah";
    server = "vpn.utah.edu";
  };

  desktop.favoriteApps = [
    "org.gnome.Nautilus.desktop"
    "org.gnome.Ptyxis.desktop"
  ];

  dconf.settings."org/gnome/shell".favorite-apps = config.desktop.favoriteApps;
}
