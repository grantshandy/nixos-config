# GNOME에 대해 한글 활성화
# Switch between US QWERTY & Hangul with <SUPER>+<SPACE>

# call this module with `home-manager` to pass along the gvariant library:
# '({ pkgs, ... }: import ./ko.nix { inherit home-manager pkgs; })'
#

{ pkgs, inputs, ... }:
{
  i18n = {
    supportedLocales = [
      "en_US.UTF-8/UTF-8"
      "ko_KR.UTF-8/UTF-8"
    ];
    inputMethod = {
      enable = true;
      type = "ibus";
      ibus.engines = [ pkgs.ibus-engines.hangul ];
    };
  };

  home-manager.sharedModules = [
    {
      dconf.settings = {
        "org/gnome/desktop/input-sources" = {
          show-all-sources = true;
          sources = with inputs.home-manager.lib.hm; [
            (gvariant.mkTuple [
              "xkb"
              "us"
            ])
            (gvariant.mkTuple [
              "ibus"
              "hangul"
            ])
          ];
        };

        "org/freedesktop/ibus/engine/hangul" = {
          hangul-keyboard = "2"; # 두벌식
          initial-input-mode = "hangul";
        };
      };
    }
  ];
}
