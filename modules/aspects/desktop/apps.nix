# The application set that comes with a graphical session.
{
  fleet.aspects.desktop-apps.tags = ["desktop"];

  flake.modules.nixos.desktop-apps = {pkgs, ...}: {
    environment.systemPackages = [pkgs.proton-vpn];
  };

  flake.modules.homeManager.desktop-apps = {
    config,
    lib,
    ...
  }: {
    desktop.favoriteApps = lib.mkOrder 400 [
      "org.gnome.Nautilus.desktop"
      "org.gnome.Ptyxis.desktop"
    ];

    dconf.settings."org/gnome/shell".favorite-apps = config.desktop.favoriteApps;
  };
}
