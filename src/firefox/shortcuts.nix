{ lib, userConfig, ... }:
{
  home-manager.sharedModules = [
    {
      xdg.desktopEntries =
        userConfig.firefox.bookmarks
        |> builtins.map (bookmark: {
          name = lib.toLower (builtins.replaceStrings [ " " ] [ "" ] bookmark.name);
          value = {
            name = bookmark.name;
            icon = "dialog-information";
            terminal = false;
            exec = "xdg-open ${shortcut.url}";
          };
        })
        |> builtins.listToAttrs;
    }
  ];
}
