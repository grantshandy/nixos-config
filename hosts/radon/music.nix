{
  config,
  pkgs,
  utils,
  ...
}: let
  mediaMount = "/mnt/media";
  musicDir = "/mnt/media/music";
  navidromeDataDir = "/mnt/media/navidrome";
  mediaMountUnit = "${utils.escapeSystemdPath mediaMount}.mount";
  mediaDeviceUnit = "${utils.escapeSystemdPath config.fileSystems.${mediaMount}.device}.device";
in {
  users.users.navidrome.extraGroups = ["media"];

  systemd.tmpfiles.rules = [
    "d ${musicDir} 2775 navidrome media - -"
    "d ${musicDir}/.beets 2775 ${config.identity.user.name} media - -"
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

  home-manager.sharedModules = [
    ({...}: {
      home.packages = [pkgs.imagemagick];

      programs.beets = {
        enable = true;
        settings = {
          directory = musicDir;
          library = "${musicDir}/.beets/library.db";

          permissions = {
            file = "664";
            dir = "2775";
          };

          import = {
            move = true;
            write = true;
          };
          plugins = ["fetchart" "embedart" "scrub" "musicbrainz" "replace" "replaygain"];

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
