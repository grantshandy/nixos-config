# enforce standard XDG bookmarks
{lib, ...}: {
  flake.modules.homeManager.gnome = {config, ...}: let
    excluded = [
      "desktop"
      "publishShare"
      "publicShare"
      "templates"
    ];

    xdgUserDirectories =
      lib.filter builtins.isString
      (lib.attrValues (removeAttrs config.xdg.userDirs excluded));
  in {
    xdg.userDirs = {
      enable = true;
      createDirectories = true;
    };

    xdg.configFile = {
      "user-dirs.dirs".force = true;
      "user-dirs.conf".force = true;
    };

    # mkAfter keeps the remote-host bookmarks contributed elsewhere at the top of
    # the Nautilus sidebar.
    gtk.gtk3.bookmarks = lib.mkAfter (map (directory: "file://${directory}") xdgUserDirectories);
  };
}
