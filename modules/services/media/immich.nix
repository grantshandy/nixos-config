# Immich, the photo library.
{config, ...}: let
  media = config.fleet.media;
  service = config.fleet.services.Immich;
in {
  fleet.services.Immich = {
    host = media.host;
    title = "Photos";
    description = "Immich photo library";
    subdomain = "photos";
    redirectPaths = ["/photos" "/photos/"];
    # Immich runs its own Authelia-backed OIDC flow, so the edge must not
    # interpose a forward-auth challenge.
    auth = "none";
    port = 2283;
    localProxy.port = 2283;
  };

  flake.modules.nixos.Immich = ( # Takes the flake-level values it needs explicitly rather than through
    # `_module.args`, so nothing here is untyped.
    {
      media,
      service,
    }: {
      config,
      inputs,
      lib,
      pkgs,
      pkgs-unstable,
      ...
    }: let
      photosDir = "${media.root}/photos";
      immichDataDir = "${media.root}/immich";
      immichPort = service.localProxy.port;
    in {
      age.secrets.immich-oidc-client-secret = {
        file = ../../../secrets/immich-oidc-client-secret.age;
        owner = config.services.immich.user;
        group = config.services.immich.group;
      };

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
          oauth = {
            enabled = true;
            issuerUrl = "https://auth.${config.identity.homelab.dns}";
            clientId = "immich";
            clientSecret._secret = config.age.secrets.immich-oidc-client-secret.path;
            tokenEndpointAuthMethod = "client_secret_post";
            scope = "openid profile email";
            signingAlgorithm = "RS256";
            profileSigningAlgorithm = "none";
            autoRegister = false;
            autoLaunch = false;
            buttonText = "Login with Authelia";
            mobileOverrideEnabled = false;
            mobileRedirectUri = "";
          };
          server.externalDomain = lib.removeSuffix "/" service.url;
        };
      };

      # Keep PostgreSQL and its VectorChord extension aligned with the Immich 3.x
      services.postgresql.package = pkgs-unstable.postgresql;

      # Preserve enough memory for SSH and core system services if Immich has a
      # transient spike. MemoryHigh throttles reclaim before MemoryMax is reached.
      systemd.slices."system-immich".sliceConfig = {
        MemoryHigh = "4G";
        MemoryMax = "5G";
        MemorySwapMax = "2G";
      };

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
    }
  ) {inherit media service;};
}
