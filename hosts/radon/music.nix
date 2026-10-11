{
  config,
  lib,
  pkgs,
  utils,
  ...
}: let
  mediaMount = "/mnt/media";
  musicDir = "/mnt/media/music";
  beetsDataDir = "${musicDir}/.beets";
  beetsLibrary = "${beetsDataDir}/library.db";
  navidromeDataDir = "/mnt/media/navidrome";
  slskdDir = "/mnt/media/slskd";
  slskdDownloadsDir = "${slskdDir}/downloads";
  slskdIncompleteDir = "${slskdDir}/incomplete";
  slskdWebPort = 5030;
  slskdListenPort = 55125;
  mediaMountUnit = "${utils.escapeSystemdPath mediaMount}.mount";
  mediaDeviceUnit = "${utils.escapeSystemdPath config.fileSystems.${mediaMount}.device}.device";
in {
  users.users.navidrome.extraGroups = ["media"];
  users.users.slskd.extraGroups = ["media"];

  systemd.tmpfiles.rules = [
    "d ${musicDir} 2775 navidrome media - -"
    "d ${beetsDataDir} 2775 ${config.identity.user.name} media - -"
    "z ${beetsLibrary} 0664 ${config.identity.user.name} media - -"
    "d ${slskdDir} 2775 slskd media - -"
    "d ${slskdDownloadsDir} 2775 slskd media - -"
    "d ${slskdIncompleteDir} 2775 slskd media - -"
  ];

  systemd.services.navidrome = {
    # Starting the drive's device unit after a hot-plug starts Navidrome again.
    wantedBy = [mediaDeviceUnit];
    after = [mediaMountUnit];
    bindsTo = [mediaMountUnit];
    unitConfig.RequiresMountsFor = [
      musicDir
      navidromeDataDir
    ];
    serviceConfig = {
      Restart = "on-failure";
      RestartSec = "5s";
    };
  };

  services.navidrome = {
    enable = true;
    openFirewall = true;
    settings = {
      Address = "0.0.0.0";
      Port = 4533;
      MusicFolder = musicDir;
      DataFolder = navidromeDataDir;
      CacheFolder = "${navidromeDataDir}/cache";
      Scanner.PurgeMissing = "always";
      CoverArtPriority = "embedded,cover.*,folder.*,front.*";
      BaseUrl = "/music";
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
      musicDir
      slskdDownloadsDir
      slskdIncompleteDir
    ];
    serviceConfig.UMask = "0002";
  };

  services.slskd = {
    enable = true;
    environmentFile = config.age.secrets.slskd-environment.path;
    openFirewall = true;
    settings = {
      directories = {
        downloads = slskdDownloadsDir;
        incomplete = slskdIncompleteDir;
      };
      shares = {
        directories = ["[Music]${musicDir}"];
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
      };
    };
  };

  # These handlers are merged ahead of Headscale's catch-all route. The slskd
  # backend remains local-only; Caddy is its sole public HTTP entry point.
  services.caddy.virtualHosts.${config.identity.homelab.dns}.extraConfig = lib.mkBefore ''
    handle /music* {
      reverse_proxy 127.0.0.1:4533
    }
    handle /slskd {
      redir /slskd/ 308
    }
    handle /slskd/* {
      reverse_proxy 127.0.0.1:${toString slskdWebPort}
    }
  '';

  home-manager.sharedModules = [
    ({...}: {
      home.packages = [pkgs.imagemagick];

      programs.beets = {
        enable = true;
        settings = {
          directory = musicDir;
          library = beetsLibrary;

          permissions = {
            file = "664";
            dir = "2775";
          };

          import = {
            move = true;
            write = true;
          };
          plugins = ["fetchart" "embedart" "scrub" "musicbrainz" "replace" "replaygain" "permissions"];

          fetchart = {
            auto = true;
            sources = ["filesystem" "coverart" "itunes" "amazon" "albumart"];
            cover_names = ["cover" "front" "folder"];
            maxwidth = 1200;
            minwidth = 320;
            cover_format = "jpg";
            quality = 85;
          };

          embedart.auto = true;
          replaygain.backend = "gstreamer";
        };
      };
    })
  ];
}
