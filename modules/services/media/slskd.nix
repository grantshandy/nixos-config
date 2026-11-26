# slskd, the Soulseek client that feeds Lidarr's download directories.
{config, ...}: let
  webPort = 5030;
  listenPort = 55125;
  media = config.fleet.media;
  service = config.fleet.services.slskd;
in {
  fleet.services.slskd = {
    host = media.host;
    description = "Soulseek client";
    path = "/slskd/";
    port = webPort;
    # slskd's own authentication is disabled, so the edge plus Authelia is the
    # only gate; its API clients need their credentials passed through untouched.
    auth = "backend";
    localProxy.port = webPort;
  };

  flake.modules.nixos.slskd = {config, ...}: {
    users.users.slskd = {
      extraGroups = ["media"];
      home = "/var/lib/slskd";
    };

    systemd.tmpfiles.rules = [
      "d ${media.slskdDir} 2775 slskd media - -"
    ];

    age.secrets.slskd-environment.file = ../../../secrets/slskd-environment.age;

    systemd.services.slskd = {
      # Stop slskd if the removable media drive disappears and restart it when
      # the drive is connected again.
      wantedBy = [config.mediaPool.deviceUnit];
      after = [config.mediaPool.mountUnit];
      bindsTo = [config.mediaPool.mountUnit];
      unitConfig.RequiresMountsFor = [
        media.library
        media.downloads
        media.incomplete
      ];
      serviceConfig.UMask = "0002";
    };

    services.slskd = {
      enable = true;
      environmentFile = config.age.secrets.slskd-environment.path;
      openFirewall = true;
      settings = {
        directories = {
          downloads = media.downloads;
          incomplete = media.incomplete;
        };
        shares = {
          directories = ["[Music]${media.library}"];
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
        soulseek.listen_port = listenPort;
        web = {
          ip_address = "127.0.0.1";
          port = webPort;
          url_base = service.basePath;
          # The edge is the only entry point and requires an Authelia session.
          authentication.disabled = true;
        };
      };
    };
  };
}
