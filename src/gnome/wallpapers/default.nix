{
  pkgs,
  lib,
  ...
}: let
  interval = "20m";
  wallpaperDir = ./.;

  gsettingsSchemas = "${pkgs.gsettings-desktop-schemas}/share/gsettings-schemas/${pkgs.gsettings-desktop-schemas.name}/glib-2.0/schemas";

  runtimeDeps = lib.makeBinPath (with pkgs; [
    coreutils
    findutils
    util-linux # flock
    imagemagick
    glib # gsettings, gdbus
    systemd # busctl
    jq
  ]);

  # Usage: cycle-wallpaper [random|reuse|resolution]
  #   random      pick a random image (default)
  #   reuse       re-render the previously chosen image (used on display changes)
  #   resolution  just print the detected desktop resolution and exit
  cycleScript = pkgs.writeShellScriptBin "cycle-wallpaper" ''
    set -euo pipefail
    export PATH="${runtimeDeps}:$PATH"

    # gsettings launched from a systemd user unit doesn't always inherit the
    # session's schema/dconf environment. Without the dconf GIO module it can
    # fall back to an in-memory backend and appear to succeed while saving nothing.
    export GSETTINGS_SCHEMA_DIR="${gsettingsSchemas}"
    export GIO_EXTRA_MODULES="${pkgs.dconf.lib}/lib/gio/modules''${GIO_EXTRA_MODULES:+:$GIO_EXTRA_MODULES}"

    # Bounding box of all logical monitors (what "spanned" stretches the image
    # over), multiplied by the largest monitor scale so HiDPI stays sharp.
    get_resolution() {
      busctl --user --json=short call \
        org.gnome.Mutter.DisplayConfig \
        /org/gnome/Mutter/DisplayConfig \
        org.gnome.Mutter.DisplayConfig \
        GetCurrentState \
      | jq -r '
          .data as [$serial, $monitors, $logical, $props]
          | [ $logical[]
              | . as $lm
              | $lm[5][0][0] as $conn
              | first(
                  $monitors[]
                  | select(.[0][0] == $conn)
                  | .[1][]
                  | select((.[6]["is-current"] | if type == "object" then .data else . end) == true)
                ) as $mode
              | (if ($lm[3] % 2) == 1
                  then [$mode[2], $mode[1]]
                  else [$mode[1], $mode[2]] end) as $px
              | { x: $lm[0], y: $lm[1], s: $lm[2],
                  w: ($px[0] / $lm[2]), h: ($px[1] / $lm[2]) }
            ] as $m
          | ($m | map(.s) | max) as $scale
          | (($m | map(.x + .w) | max) - ($m | map(.x) | min)) as $w
          | (($m | map(.y + .h) | max) - ($m | map(.y) | min)) as $h
          | "\(($w * $scale) | round)x\(($h * $scale) | round)"
        '
    }

    MODE="''${1:-random}"

    if [ "$MODE" = "resolution" ]; then
      get_resolution
      exit 0
    fi

    # Output lives somewhere persistent (NOT /run/user, which is wiped on boot).
    STATE_DIR="''${XDG_STATE_HOME:-$HOME/.local/state}/wallpaper-cycler"
    mkdir -p "$STATE_DIR"

    # Serialize runs (login run vs. timer vs. display-change watcher).
    exec 9>"$STATE_DIR/lock"
    flock 9

    SOURCE=""
    if [ "$MODE" = "reuse" ] && [ -f "$STATE_DIR/source" ]; then
      SOURCE="$(cat "$STATE_DIR/source")"
      [ -f "$SOURCE" ] || SOURCE=""
    fi

    if [ -z "$SOURCE" ]; then
      SOURCE="$(find "${wallpaperDir}" -type f \
        \( -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' \) \
        | shuf -n 1)"
    fi

    if [ -z "$SOURCE" ]; then
      echo "No wallpapers found in ${wallpaperDir}" >&2
      exit 1
    fi

    RES="$(get_resolution 2>/dev/null || true)"
    if [ -z "$RES" ]; then
      echo "Could not detect display resolution, falling back to 1920x1080" >&2
      RES="1920x1080"
    fi

    echo "Setting wallpaper to: $SOURCE ($RES)"

    # Force the plain jpeg/png decoder instead of letting ImageMagick
    # content-sniff the file. Without this, phone photos with an embedded
    # Ultra HDR gain map get routed through the (buggy) uhdr coder, which
    # can fail mid-transform and leave a broken/blank output file.
    case "''${SOURCE,,}" in
      *.png) FORMAT="png" ;;
      *) FORMAT="jpeg" ;;
    esac

    # Unique filename per run => picture-uri actually changes => GNOME reloads.
    OUT="$STATE_DIR/wallpaper-$(date +%s%N).jpg"
    TMP="$STATE_DIR/wallpaper-partial-$$.jpg"

    magick "''${FORMAT}:$SOURCE" \
      -strip \
      -resize "$RES^" \
      -gravity Center \
      -extent "$RES" \
      -quality 92 \
      "$TMP"
    mv "$TMP" "$OUT" # atomic: GNOME never sees a half-written file

    URI="file://$OUT"
    gsettings set org.gnome.desktop.background picture-options "spanned"
    gsettings set org.gnome.desktop.background picture-uri "$URI"
    gsettings set org.gnome.desktop.background picture-uri-dark "$URI"

    echo "$SOURCE" > "$STATE_DIR/source"

    # Prune old renders (keep anything <1 min old so crossfades don't hit a missing file).
    find "$STATE_DIR" -maxdepth 1 -name 'wallpaper-*.jpg' \
      ! -name "$(basename "$OUT")" -mmin +1 -delete
  '';

  watcherScript = pkgs.writeShellScriptBin "wallpaper-display-watcher" ''
    export PATH="${runtimeDeps}:$PATH"

    gdbus monitor --session \
      --dest org.gnome.Mutter.DisplayConfig \
      --object-path /org/gnome/Mutter/DisplayConfig \
    | while read -r line; do
        case "$line" in
          *MonitorsChanged*) ;;
          *) continue ;;
        esac

        # Hotplugging usually emits a burst of signals; wait for it to settle.
        while read -r -t 3 _; do :; done

        echo "Monitor layout changed, re-rendering wallpaper"
        ${lib.getExe cycleScript} reuse || echo "cycle-wallpaper failed" >&2
      done
  '';
in {
  home-manager.sharedModules = [
    {
      home.packages = [cycleScript];

      # Runs once at login and then on every timer tick.
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
          OnStartupSec = interval;
          OnUnitActiveSec = interval;
        };
        Install.WantedBy = ["timers.target"];
      };

      # Re-renders the current wallpaper whenever the monitor layout changes.
      systemd.user.services.wallpaper-display-watcher = {
        Unit = {
          Description = "Re-render wallpaper when displays change";
          After = ["graphical-session.target"];
          PartOf = ["graphical-session.target"];
        };

        Service = {
          ExecStart = lib.getExe watcherScript;
          Restart = "always";
          RestartSec = "5";
        };

        Install.WantedBy = ["graphical-session.target"];
      };
    }
  ];
}
