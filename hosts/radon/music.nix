{
  config,
  lib,
  pkgs,
  utils,
  ...
}: let
  mediaMount = "/mnt/media";
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
  my.slskdNotify.server.enable = true;

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
    after = [mediaMountUnit];
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
      BaseUrl = "/music";
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
        LIDARR__SERVER__URLBASE = "/lidarr";
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

  age.secrets.slskd-environment.file = ../../secrets/slskd-environment.age;

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
        url_base = "/slskd";
        # Caddy is the only entry point and requires an Authelia session.
        authentication.disabled = true;
      };
    };
  };

  # These handlers are merged ahead of Headscale's catch-all route. The web
  # backends remain off the public interface; Caddy is their public entry point.
  services.caddy.virtualHosts.${config.identity.homelab.dns}.extraConfig = lib.mkBefore ''
    handle /music {
      redir * /music/ 308
    }
    handle /music/* {
      reverse_proxy 127.0.0.1:${toString navidromePort}
    }

    handle /lidarr {
      redir * /lidarr/ 308
    }
    handle /lidarr/* {
      forward_auth 127.0.0.1:9091 {
        uri /api/authz/forward-auth
        # Keep Lidarr's API credentials out of the cloned auth request. The
        # original request still reaches Lidarr with these values unchanged.
        header_up -Authorization
        header_up -X-Api-Key
        header_up X-Forwarded-URI {http.request.uri.path}
        copy_headers Remote-User Remote-Groups Remote-Email Remote-Name
      }
      reverse_proxy 127.0.0.1:${toString lidarrPort}
    }

    handle /slskd {
      redir * /slskd/ 308
    }
    handle /slskd/* {
      forward_auth 127.0.0.1:9091 {
        uri /api/authz/forward-auth
        # slskd also uses bearer tokens and access_token query parameters for
        # its API and SignalR connections. Only hide them from Authelia.
        header_up -Authorization
        header_up X-Forwarded-URI {http.request.uri.path}
        copy_headers Remote-User Remote-Groups Remote-Email Remote-Name
      }
      reverse_proxy 127.0.0.1:${toString slskdWebPort}
    }
  '';
}
