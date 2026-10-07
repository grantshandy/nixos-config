{
  config,
  inputs,
  lib,
  pkgs,
  pkgs-unstable,
  ...
}: let
  photosDir = "/mnt/media/photos";
  immichDataDir = "/mnt/media/immich";
  immichPort = 2283;
  photosHost = "photos.${config.identity.homelab.dns}";
in {
  disabledModules = ["services/web-apps/immich.nix"];
  imports = ["${inputs.nixpkgs-unstable}/nixos/modules/services/web-apps/immich.nix"];

  users.users.immich.extraGroups = ["media"];

  services.immich = {
    enable = true;
    package = pkgs-unstable.immich;
    host = "127.0.0.1";
    port = immichPort;
    openFirewall = false;
    mediaLocation = immichDataDir;

    # Start with CPU inference; CUDA requires a compatible proprietary driver
    # and inference libraries, not just an NVIDIA display adapter.
    machine-learning.enable = true;
    settings = {
      machineLearning = {
        enabled = true;
        facialRecognition = {
          enabled = true;
          modelName = "buffalo_l";
        };
      };
      newVersionCheck.enabled = false;
      server.externalDomain = "https://${photosHost}";
    };
  };

  # Keep PostgreSQL and its VectorChord extension aligned with the Immich 3.x
  services.postgresql.package = pkgs-unstable.postgresql;

  systemd.services.immich-machine-learning.serviceConfig = {
    IOSchedulingClass = "idle";
    Nice = 10;
  };

  systemd.services.immich-server = {
    unitConfig.RequiresMountsFor = [photosDir immichDataDir];
    serviceConfig = {
      BindReadOnlyPaths = [photosDir];
      ExecStartPre = lib.mkBefore [
        "+${lib.getExe' pkgs.coreutils "install"} -d -m 0700 -o immich -g immich ${immichDataDir}"
      ];
      IOSchedulingClass = "idle";
      Nice = 10;
    };
  };

  services.caddy.virtualHosts = {
    ${config.identity.homelab.dns}.extraConfig = lib.mkBefore ''
      redir /photos https://${photosHost}/ 308
      redir /photos/ https://${photosHost}/ 308
    '';

    ${photosHost}.extraConfig = ''
      reverse_proxy 127.0.0.1:${toString immichPort}
    '';
  };
}
