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
  # The release channel still contains unsupported Immich 2.x.  Use the
  # already-pinned unstable module and package, which currently provide the
  # supported 3.x release, without allowing known-insecure packages globally.
  disabledModules = ["services/web-apps/immich.nix"];
  imports = ["${inputs.nixpkgs-unstable}/nixos/modules/services/web-apps/immich.nix"];

  # The existing photo collection is an external library.  Keep it read-only so
  # an Immich bug or compromised service cannot alter the originals.
  users.users.immich.extraGroups = ["media"];

  services.immich = {
    enable = true;
    package = pkgs-unstable.immich;
    host = "127.0.0.1";
    port = immichPort;
    openFirewall = false;
    mediaLocation = immichDataDir;

    # Do not install or run the model server on this Raspberry Pi.  Disabling
    # machine learning in Immich itself also prevents face/smart-search jobs
    # from being queued against a server that is intentionally absent.
    machine-learning.enable = false;
    settings = {
      machineLearning.enabled = false;
      newVersionCheck.enabled = false;
      server.externalDomain = "https://${photosHost}";
    };
  };

  # Keep PostgreSQL and its VectorChord extension aligned with the Immich 3.x
  services.postgresql.package = pkgs-unstable.postgresql;

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
