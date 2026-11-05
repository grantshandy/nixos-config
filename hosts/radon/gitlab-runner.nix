{
  config,
  lib,
  pkgs,
  ...
}: let
  tokenFile = ../../secrets/gitlab-runner-token.age;
  tokenAvailable = builtins.pathExists tokenFile;
in
  lib.mkIf tokenAvailable {
    age.secrets.gitlab-runner-token.file = tokenFile;

    services.gitlab-runner = {
      enable = true;
      settings.concurrent = 1;
      extraPackages = [
        config.nix.package
        pkgs.git
      ];

      services.radon-nix = {
        authenticationTokenConfigFile = config.age.secrets.gitlab-runner-token.path;
        executor = "shell";
        description = "radon-nix";
        environmentVariables.NIX_CONFIG = ''
          experimental-features = nix-command flakes pipe-operators
        '';
      };
    };

    # Keep CI workloads lower priority than Radon's interactive and hosted services.
    systemd.services.gitlab-runner.serviceConfig = {
      Nice = 10;
      CPUWeight = 25;
      IOWeight = 25;
      OOMScoreAdjust = 500;
    };
  }
