{
  pkgs,
  lib,
  userConfig,
  ...
}: let
  interval = "20m";

  cycleScript = pkgs.writeShellScriptBin "cycle-wallpaper" ''
    set -euo pipefail

    TARGET=$(${pkgs.findutils}/bin/find "${./.}" \
      -type f \( -name "*.jpg" -o -name "*.png" -o -name "*.jpeg" \) \
      | ${pkgs.coreutils}/bin/shuf -n 1)

    if [ -z "$TARGET" ]; then
      echo "No wallpapers found in ${./.}"
      exit 1
    fi

    echo "Setting wallpaper to: $TARGET"

    # Force the plain jpeg/png decoder instead of letting ImageMagick
    # content-sniff the file. Without this, phone photos with an embedded
    # Ultra HDR gain map get routed through the (buggy) uhdr coder, which
    # can fail mid-transform and leave a broken/blank output file.
    case "$TARGET" in
      *.png|*.PNG) FORMAT="png" ;;
      *) FORMAT="jpeg" ;;
    esac

    CONVERTED="''${XDG_RUNTIME_DIR:-/tmp}/wallpaper-current.jpg"
    ${lib.getExe pkgs.imagemagick} "''${FORMAT}:$TARGET" \
      -strip \
      -resize ${userConfig.resolution}^ \
      -gravity Center \
      -extent ${userConfig.resolution} \
      "$CONVERTED"

    ${pkgs.glib}/bin/gsettings set org.gnome.desktop.background picture-uri "file://$CONVERTED"
    ${pkgs.glib}/bin/gsettings set org.gnome.desktop.background picture-uri-dark "file://$CONVERTED"
    ${pkgs.glib}/bin/gsettings set org.gnome.desktop.background picture-options "spanned"
  '';
in {
  home-manager.sharedModules = [
    {
      home.packages = [cycleScript];

      systemd.user.services.wallpaper-cycler = {
        Unit = {
          Description = "Randomly cycle GNOME wallpaper";
          After = ["graphical-session.target"];
        };

        Service = {
          Type = "oneshot";
          ExecStart = lib.getExe cycleScript;
          IOSchedulingClass = "idle";
        };

        Install.WantedBy = ["graphical-session.target"];
      };

      systemd.user.timers.wallpaper-cycler = {
        Unit.Description = "Timer for wallpaper cycling";
        Timer = {
          OnBootSec = "5m";
          OnUnitActiveSec = interval;
          Persistent = true;
        };
        Install.WantedBy = ["timers.target"];
      };
    }
  ];
}
