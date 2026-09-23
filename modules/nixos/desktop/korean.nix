# GNOME에 대해 한글 활성화
# Switch between US QWERTY & Hangul with <SUPER>+<SPACE>
{pkgs, ...}: {
  i18n = {
    supportedLocales = [
      "en_US.UTF-8/UTF-8"
      "ko_KR.UTF-8/UTF-8"
    ];
    inputMethod = {
      enable = true;
      type = "ibus";
      ibus.engines = with pkgs.ibus-engines; [hangul];
    };
  };

  home-manager.sharedModules = [
    ({lib, ...}: {
      dconf.settings = {
        "org/gnome/desktop/input-sources" = {
          show-all-sources = true;
          sources = [
            (lib.hm.gvariant.mkTuple ["xkb" "us"])
            (lib.hm.gvariant.mkTuple ["ibus" "hangul"])
          ];
        };

        "org/freedesktop/ibus/engine/hangul" = {
          hangul-keyboard = "2"; # 2 = Dubeolsik (standard)
          initial-input-mode = "hangul";
        };
      };
    })
  ];
}
