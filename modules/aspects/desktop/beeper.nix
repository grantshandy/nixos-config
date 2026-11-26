{
  fleet.aspects.beeper.tags = ["desktop"];

  flake.modules.homeManager.beeper = {
    lib,
    pkgs-unstable,
    ...
  }: {
    home.packages = [pkgs-unstable.beeper];

    # Explicit order: the dash layout is declared intent, not an accident of the
    # order the aspect files happen to be traversed in.
    desktop.favoriteApps = lib.mkOrder 100 ["beepertexts.desktop"];
  };
}
