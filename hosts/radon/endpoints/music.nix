{
  config,
  lib,
  pkgs,
  inputs,
  radonCaddyHost,
  radonMediaRoot,
  radonEndpoints,
  utils,
  ...
}: let
  mediaMount = radonMediaRoot;
  legacyMusicDir = "${mediaMount}/music";
  lidarrDir = "${mediaMount}/lidarr";
  lidarrConfigDir = "${lidarrDir}/config";
  lidarrMusicDir = "${lidarrDir}/library";
  lidarrDownloadsDir = "${lidarrDir}/downloads";
  lidarrIncompleteDir = "${lidarrDir}/incomplete";
  tubifarryDir = "${lidarrConfigDir}/plugins/TypNull/Tubifarry";
  lidarrPort = 8686;
  lidarrUid = 986;
  navidromeDataDir = "${mediaMount}/navidrome";
  navidromePort = 4533;
  navidromeBackgroundPort = 4534;
  navidromeBackgroundPath = "${radonEndpoints.Navidrome.path}login-background";
  wallpaperSourceDir = inputs.wallpapers-images;
  navidromeWallpapers = pkgs.runCommand "navidrome-login-wallpapers" {nativeBuildInputs = [pkgs.imagemagick];} ''
    mkdir -p "$out"

    for source in ${wallpaperSourceDir}/*; do
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
  navidromeBackgroundServer = pkgs.writeShellScriptBin "navidrome-background-server" ''
    exec ${lib.getExe pkgs.python3} ${pkgs.writeText "navidrome-background-server.py" ''
      import secrets
      import shutil
      from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
      from pathlib import Path

      wallpaper_dir = Path("${navidromeWallpapers}")
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

      ThreadingHTTPServer(("127.0.0.1", ${toString navidromeBackgroundPort}), BackgroundHandler).serve_forever()
    ''}
  '';
  slskdDir = "${mediaMount}/slskd";
  slskdWebPort = 5030;
  slskdListenPort = 55125;
  mediaMountUnit = "${utils.escapeSystemdPath mediaMount}.mount";
  mediaDeviceUnit = "${utils.escapeSystemdPath config.fileSystems.${mediaMount}.device}.device";

  tubifarry = pkgs.fetchzip {
    url = "https://github.com/TypNull/Tubifarry/releases/download/v2.3.1/Tubifarry-v2.3.1.net8.0.zip";
    hash = "sha256-bBtEuplDHqLC1eNhjrZUQSSemkSR2VhfqpRRoCuK7zE=";
    stripRoot = false;
  };
in {
  networking.firewall.interfaces.tailscale0.allowedTCPPorts = [navidromePort];

  users.users = {
    lidarr = {
      isSystemUser = true;
      uid = lidarrUid;
      group = "media";
      home = lidarrConfigDir;
    };
    navidrome.extraGroups = ["media"];
    slskd = {
      extraGroups = ["media"];
      home = "/var/lib/slskd";
    };
  };

  systemd.tmpfiles.rules = [
    "d ${legacyMusicDir} 2775 navidrome media - -"
    "d ${slskdDir} 2775 slskd media - -"
    "d ${lidarrDir} 2775 lidarr media - -"
    "d ${lidarrConfigDir} 2775 lidarr media - -"
    "d ${lidarrMusicDir} 2775 lidarr media - -"
    "d ${lidarrDownloadsDir} 2775 lidarr media - -"
    "d ${lidarrIncompleteDir} 2775 lidarr media - -"
  ];

  systemd.services.navidrome = {
    # Starting the drive's device unit after a hot-plug starts Navidrome again.
    wantedBy = [mediaDeviceUnit];
    wants = ["navidrome-backgrounds.service"];
    after = [mediaMountUnit "navidrome-backgrounds.service"];
    bindsTo = [mediaMountUnit];
    unitConfig.RequiresMountsFor = [
      lidarrMusicDir
      navidromeDataDir
    ];
    serviceConfig = {
      Restart = "on-failure";
      RestartSec = "5s";
    };
  };

  systemd.services.navidrome-backgrounds = {
    description = "Serve random Navidrome login backgrounds";
    serviceConfig = {
      ExecStart = lib.getExe navidromeBackgroundServer;
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
      Port = navidromePort;
      MusicFolder = lidarrMusicDir;
      DataFolder = navidromeDataDir;
      CacheFolder = "${navidromeDataDir}/cache";
      Scanner.PurgeMissing = "always";
      CoverArtPriority = "embedded,cover.*,folder.*,front.*";
      BaseUrl = radonEndpoints.Navidrome.basePath;
      UILoginBackgroundUrl = "/login-background";
    };
  };

  virtualisation.podman.enable = true;
  virtualisation.oci-containers = {
    backend = "podman";
    containers.lidarr = {
      image = "lscr.io/linuxserver/lidarr@sha256:605cc68b60c491e05014194ebba0f61b8eb424ae8f97f289eb715686b454e10c";
      autoStart = true;
      environment = {
        PUID = toString lidarrUid;
        PGID = "998";
        UMASK = "002";
        TZ = config.time.timeZone;
        LIDARR__AUTH__METHOD = "External";
        LIDARR__AUTH__REQUIRED = "Enabled";
        LIDARR__SERVER__BINDADDRESS = "127.0.0.1";
        LIDARR__SERVER__PORT = toString lidarrPort;
        LIDARR__SERVER__URLBASE = radonEndpoints.Lidarr.basePath;
      };
      volumes = [
        "${lidarrConfigDir}:/config"
        "${lidarrDir}:${lidarrDir}"
      ];
      extraOptions = ["--network=host"];
    };
  };

  systemd.services.lidarr-tubifarry = {
    description = "Install the pinned Tubifarry plugin for Lidarr";
    before = ["podman-lidarr.service"];
    after = [mediaMountUnit];
    bindsTo = [mediaMountUnit];
    unitConfig.RequiresMountsFor = [lidarrConfigDir];
    serviceConfig.Type = "oneshot";
    script = ''
      install -d -m 0770 -o lidarr -g media ${tubifarryDir}
      find ${tubifarryDir} -mindepth 1 -maxdepth 1 ! -name settings.resx -exec rm -rf -- {} +
      cp -R ${tubifarry}/. ${tubifarryDir}/
      chown -R lidarr:media ${tubifarryDir}
      chmod -R u+rwX,g+rwX,o-rwx ${tubifarryDir}
    '';
  };

  systemd.services.podman-lidarr = {
    wantedBy = [mediaDeviceUnit];
    requires = ["lidarr-tubifarry.service"];
    after = [mediaMountUnit "lidarr-tubifarry.service" "slskd.service"];
    bindsTo = [mediaMountUnit];
    unitConfig.RequiresMountsFor = [
      lidarrConfigDir
      lidarrMusicDir
      lidarrDownloadsDir
      lidarrIncompleteDir
    ];
    serviceConfig = {
      Restart = "on-failure";
      RestartSec = "5s";
    };
  };

  age.secrets.slskd-environment.file = ../../../secrets/slskd-environment.age;

  systemd.services.slskd = {
    # Stop slskd if the removable media drive disappears and restart it when
    # the drive is connected again.
    wantedBy = [mediaDeviceUnit];
    after = [mediaMountUnit];
    bindsTo = [mediaMountUnit];
    unitConfig.RequiresMountsFor = [
      lidarrMusicDir
      lidarrDownloadsDir
      lidarrIncompleteDir
    ];
    serviceConfig.UMask = "0002";
  };

  services.slskd = {
    enable = true;
    environmentFile = config.age.secrets.slskd-environment.path;
    openFirewall = true;
    settings = {
      directories = {
        downloads = lidarrDownloadsDir;
        incomplete = lidarrIncompleteDir;
      };
      shares = {
        directories = ["[Music]${lidarrMusicDir}"];
        cache.retention = 60;
      };
      global = {
        upload = {
          slots = 5;
          speed_limit = 10240;
        };
        limits.queued = {
          files = 250;
          megabytes = 20480;
        };
      };
      soulseek.listen_port = slskdListenPort;
      web = {
        ip_address = "127.0.0.1";
        port = slskdWebPort;
        url_base = radonEndpoints.slskd.basePath;
        # Caddy is the only entry point and requires an Authelia session.
        authentication.disabled = true;
      };
    };
  };

  # These handlers are merged ahead of Headscale's catch-all route. The web
  # backends remain off the public interface; Caddy is their public entry point.
  services.caddy.virtualHosts = lib.mkMerge [
    {
      ${radonCaddyHost radonEndpoints.Navidrome.host}.extraConfig = lib.mkBefore ''
        ${lib.optionalString (radonEndpoints.Navidrome.basePath != "") ''
          handle ${radonEndpoints.Navidrome.basePath} {
            redir * ${radonEndpoints.Navidrome.path} 308
          }
        ''}
            handle ${navidromeBackgroundPath} {
              reverse_proxy 127.0.0.1:${toString navidromeBackgroundPort}
            }

            handle ${radonEndpoints.Navidrome.path}* {
              reverse_proxy 127.0.0.1:${toString navidromePort}
            }

      '';
    }
    {
      ${radonCaddyHost radonEndpoints.Lidarr.host}.extraConfig = lib.mkBefore ''
        ${lib.optionalString (radonEndpoints.Lidarr.basePath != "") ''
          handle ${radonEndpoints.Lidarr.basePath} {
            redir * ${radonEndpoints.Lidarr.path} 308
          }
        ''}
            handle ${radonEndpoints.Lidarr.path}* {
              reverse_proxy 127.0.0.1:${toString lidarrPort}
            }

      '';
    }
    {
      ${radonCaddyHost radonEndpoints.slskd.host}.extraConfig = lib.mkBefore ''
        ${lib.optionalString (radonEndpoints.slskd.basePath != "") ''
          handle ${radonEndpoints.slskd.basePath} {
            redir * ${radonEndpoints.slskd.path} 308
          }
        ''}
            handle ${radonEndpoints.slskd.path}* {
              reverse_proxy 127.0.0.1:${toString slskdWebPort}
            }
      '';
    }
  ];
}
