# Navidrome, serving the library Lidarr curates.
{config, ...}: let
  port = 4533;
  backgroundPort = 4534;
  media = config.fleet.media;
  service = config.fleet.services.Navidrome;
  wallpaperDir = config.fleet.wallpapers.directory;
  backgroundPath = "login-background";
in {
  fleet.services.Navidrome = {
    inherit port;

    host = media.host;
    title = "Music";
    description = "Navidrome music library";
    path = "/music/";
    auth = "none";
    localProxy.port = port;
    localProxy.extraConfig = ''
      handle ${service.path}${backgroundPath} {
        reverse_proxy 127.0.0.1:${toString backgroundPort}
      }
    '';
  };

  flake.modules.nixos.Navidrome = {
    config,
    lib,
    pkgs,
    ...
  }: let
    wallpapers = pkgs.runCommand "navidrome-login-wallpapers" {nativeBuildInputs = [pkgs.imagemagick];} ''
      mkdir -p "$out"

      for source in ${wallpaperDir}/*; do
        case "$source" in
          *.jpg | *.jpeg) decoder=jpeg ;;
          *.png) decoder=png ;;
          *) continue ;;
        esac

        filename="$(basename "$source")"
        magick "$decoder:$source" \
          -auto-orient \
          -strip \
          -resize "1920x1080>" \
          -quality 82 \
          "$out/$filename"
      done
    '';

    backgroundServer = pkgs.writeShellScriptBin "navidrome-background-server" ''
      exec ${lib.getExe pkgs.python3} ${pkgs.writeText "navidrome-background-server.py" ''
        import secrets
        import shutil
        from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
        from pathlib import Path

        wallpaper_dir = Path("${wallpapers}")
        wallpapers = tuple(
            path
            for path in wallpaper_dir.iterdir()
            if path.is_file() and path.suffix.lower() in {".jpg", ".jpeg", ".png"}
        )

        if not wallpapers:
            raise RuntimeError(f"No wallpapers found in {wallpaper_dir}")

        class BackgroundHandler(BaseHTTPRequestHandler):
            def do_GET(self):
                wallpaper = secrets.choice(wallpapers)
                content_type = "image/png" if wallpaper.suffix.lower() == ".png" else "image/jpeg"
                self.send_response(200)
                self.send_header("Content-Type", content_type)
                self.send_header("Content-Length", str(wallpaper.stat().st_size))
                self.send_header("Cache-Control", "no-store")
                self.end_headers()
                with wallpaper.open("rb") as image:
                    shutil.copyfileobj(image, self.wfile)

            def log_message(self, format, *args):
                return

        ThreadingHTTPServer(("127.0.0.1", ${toString backgroundPort}), BackgroundHandler).serve_forever()
      ''}
    '';
  in {
    networking.firewall.interfaces.tailscale0.allowedTCPPorts = [port];

    users.users.navidrome.extraGroups = ["media"];

    systemd.tmpfiles.rules = [
      "d ${media.legacyMusic} 2775 navidrome media - -"
    ];

    systemd.services.navidrome = {
      # Starting the drive's device unit after a hot-plug starts Navidrome again.
      wantedBy = [config.mediaPool.deviceUnit];
      wants = ["navidrome-backgrounds.service"];
      after = [config.mediaPool.mountUnit "navidrome-backgrounds.service"];
      bindsTo = [config.mediaPool.mountUnit];
      unitConfig.RequiresMountsFor = [
        media.library
        media.navidromeData
      ];
      serviceConfig = {
        Restart = "on-failure";
        RestartSec = "5s";
      };
    };

    systemd.services.navidrome-backgrounds = {
      description = "Serve random Navidrome login backgrounds";
      serviceConfig = {
        ExecStart = lib.getExe backgroundServer;
        DynamicUser = true;
        Restart = "on-failure";
        RestartSec = "5s";
        NoNewPrivileges = true;
        PrivateTmp = true;
        ProtectHome = true;
        ProtectSystem = "strict";
      };
    };

    services.navidrome = {
      enable = true;
      openFirewall = false;
      settings = {
        Address = "0.0.0.0";
        Port = port;
        MusicFolder = media.library;
        DataFolder = media.navidromeData;
        CacheFolder = "${media.navidromeData}/cache";
        Scanner.PurgeMissing = "always";
        CoverArtPriority = "embedded,cover.*,folder.*,front.*";
        BaseUrl = service.basePath;
        UILoginBackgroundUrl = "/${backgroundPath}";
      };
    };
  };
}
