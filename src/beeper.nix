{pkgs-unstable, ...}: {
  home-manager.sharedModules = [
    {
      home.packages = [pkgs-unstable.beeper];

      dconf.settings."org/gnome/shell".favorite-apps = ["beepertexts.desktop"];
    }
  ];
}
