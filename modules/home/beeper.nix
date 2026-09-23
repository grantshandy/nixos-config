{pkgs-unstable, ...}: {
  home.packages = [pkgs-unstable.beeper];

  desktop.favoriteApps = ["beepertexts.desktop"];
}
