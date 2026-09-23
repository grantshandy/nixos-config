{
  config,
  pkgs,
  ...
}: let
  musicDir = "/media/music";
in {
  ##############################################################
  ## Shared Media Group & Permissions
  ##############################################################
  users.groups.media = {};
  users.users.navidrome.extraGroups = ["media"];
  users.users.${config.identity.user.name}.extraGroups = ["media"];

  systemd.tmpfiles.rules = [
    "d /media 0755 root root - -"
    "d ${musicDir} 2775 navidrome media - -"
    "d ${musicDir}/.beets 2775 ${config.identity.user.name} media - -"
  ];

  systemd.services.media-acl-init = {
    description = "Apply recursive default ACL for media group under ${musicDir}";
    wantedBy = ["multi-user.target"];
    before = ["navidrome.service"];
    after = ["local-fs.target"];
    serviceConfig.Type = "oneshot";
    script = ''
      ${pkgs.acl}/bin/setfacl -R -m g:media:rwx -d -m g:media:rwx ${musicDir}
    '';
  };

  systemd.services.navidrome = {
    after = ["media-acl-init.service"];
    requires = ["media-acl-init.service"];
  };

  services.navidrome = {
    enable = true;
    openFirewall = true;
    settings = {
      MusicFolder = musicDir;
      Address = "0.0.0.0";
      Scanner.PurgeMissing = "always";
      CoverArtPriority = "cover.*,folder.*,front.*";
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

          # Force beets to write imported files with group write access
          permfile = "0664";
          permdir = "0775";

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
