{
  pkgs,
  lib,
  ...
}: let
  interval = "20m";

  cycleScript = pkgs.writeShellScriptBin "cycle-wallpaper" ''
    TARGET=$(${pkgs.findutils}/bin/find "${./.}" \
      -type f \( -name "*.jpg" -o -name "*.png" -o -name "*.jpeg" \) \
      | ${pkgs.coreutils}/bin/shuf -n 1)

    if [ -z "$TARGET" ]; then
      echo "No wallpapers found in ${./.}"
      exit 1
    fi

    echo "Setting wallpaper to: $TARGET"

    ${pkgs.glib}/bin/gsettings set org.gnome.desktop.background picture-uri "file://$TARGET"
    ${pkgs.glib}/bin/gsettings set org.gnome.desktop.background picture-uri-dark "file://$TARGET"
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
