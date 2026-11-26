# Contributes to the same `gnome` aspect as ./gnome.nix -- several files may
# extend one aspect, so an incremental addition is a new file rather than an
# edit to an existing one.
{
  flake.modules.homeManager.gnome = {pkgs, ...}: let
    extensions = with pkgs.gnomeExtensions; [
      blur-my-shell # make overview background blurred background image. Very nice.
      pip-on-top
    ];
  in {
    home.packages = extensions;

    dconf.settings = {
      "org/gnome/shell" = {
        disable-user-extensions = false;
        enabled-extensions = pkgs.lib.lists.forEach extensions (ext: ext.passthru.extensionUuid);
      };

      "org/gnome/shell/extensions/blur-my-shell/panel".override-background-dynamically = true;
      "org/gnome/shell/extensions/pip-on-top".stick = true;
    };
  };
}
