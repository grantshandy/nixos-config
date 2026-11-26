# Lidarr, which owns the canonical music library and its download staging
# directories. Runs as a pinned container because the Tubifarry plugin tracks
# upstream releases rather than nixpkgs.
{config, ...}: let
  port = 8686;
  uid = 986;
  media = config.fleet.media;
  service = config.fleet.services.Lidarr;
in {
  fleet.services.Lidarr = {
    host = media.host;
    description = "Music collection management";
    path = "/lidarr/";
    inherit port;
    # slskd's and Lidarr's API clients need their credentials passed through to
    # the backend untouched.
    auth = "backend";
    localProxy.port = port;
  };

  flake.modules.nixos.Lidarr = {
    config,
    pkgs,
    ...
  }: let
    pluginDir = "${media.lidarrConfig}/plugins/TypNull/Tubifarry";

    tubifarry = pkgs.fetchzip {
      url = "https://github.com/TypNull/Tubifarry/releases/download/v2.3.1/Tubifarry-v2.3.1.net8.0.zip";
      hash = "sha256-bBtEuplDHqLC1eNhjrZUQSSemkSR2VhfqpRRoCuK7zE=";
      stripRoot = false;
    };
  in {
    users.users.lidarr = {
      isSystemUser = true;
      inherit uid;
      group = "media";
      home = media.lidarrConfig;
    };

    systemd.tmpfiles.rules = [
      "d ${media.lidarrDir} 2775 lidarr media - -"
      "d ${media.lidarrConfig} 2775 lidarr media - -"
      "d ${media.library} 2775 lidarr media - -"
      "d ${media.downloads} 2775 lidarr media - -"
      "d ${media.incomplete} 2775 lidarr media - -"
    ];

    virtualisation.podman.enable = true;
    virtualisation.oci-containers = {
      backend = "podman";
      containers.lidarr = {
        image = "lscr.io/linuxserver/lidarr@sha256:605cc68b60c491e05014194ebba0f61b8eb424ae8f97f289eb715686b454e10c";
        autoStart = true;
        environment = {
          PUID = toString uid;
          PGID = "998";
          UMASK = "002";
          TZ = config.time.timeZone;
          LIDARR__AUTH__METHOD = "External";
          LIDARR__AUTH__REQUIRED = "Enabled";
          LIDARR__SERVER__BINDADDRESS = "127.0.0.1";
          LIDARR__SERVER__PORT = toString port;
          LIDARR__SERVER__URLBASE = service.basePath;
        };
        volumes = [
          "${media.lidarrConfig}:/config"
          "${media.lidarrDir}:${media.lidarrDir}"
        ];
        extraOptions = ["--network=host"];
      };
    };

    systemd.services.lidarr-tubifarry = {
      description = "Install the pinned Tubifarry plugin for Lidarr";
      before = ["podman-lidarr.service"];
      after = [config.mediaPool.mountUnit];
      bindsTo = [config.mediaPool.mountUnit];
      unitConfig.RequiresMountsFor = [media.lidarrConfig];
      serviceConfig.Type = "oneshot";
      script = ''
        install -d -m 0770 -o lidarr -g media ${pluginDir}
        find ${pluginDir} -mindepth 1 -maxdepth 1 ! -name settings.resx -exec rm -rf -- {} +
        cp -R ${tubifarry}/. ${pluginDir}/
        chown -R lidarr:media ${pluginDir}
        chmod -R u+rwX,g+rwX,o-rwx ${pluginDir}
      '';
    };

    systemd.services.podman-lidarr = {
      wantedBy = [config.mediaPool.deviceUnit];
      requires = ["lidarr-tubifarry.service"];
      after = [config.mediaPool.mountUnit "lidarr-tubifarry.service" "slskd.service"];
      bindsTo = [config.mediaPool.mountUnit];
      unitConfig.RequiresMountsFor = [
        media.lidarrConfig
        media.library
        media.downloads
        media.incomplete
      ];
      serviceConfig = {
        Restart = "on-failure";
        RestartSec = "5s";
      };
    };
  };
}
