{
  pkgs,
  config,
  lib,
  ...
}: {
  i18n = let
    lc = "en_US.UTF-8";
  in {
    defaultLocale = lc;
    extraLocaleSettings.LC_ALL = lc;
  };

  nixpkgs.config.allowUnfree = true;
  nix.settings =
    {
      experimental-features = [
        "nix-command"
        "flakes"
        "pipe-operators"
      ];
      auto-optimise-store = true;
    }
    // lib.optionalAttrs (config.networking.hostName != "radon") {
      substituters = lib.mkBefore ["http://radon:5000?priority=10"];
      trusted-public-keys = lib.mkBefore [
        "radon-1:/Bp+bJdtCCKSBVv+DP5dYx2yz+75ScD5ZHVC5C7cx4k="
      ];
    };
  documentation.nixos.enable = false;

  users.users."${config.identity.user.name}" = {
    isNormalUser = true;
    description = config.identity.user.description;
    extraGroups = [
      "networkmanager"
      "wheel"
    ];
    packages = with pkgs; [git];
  };

  system.stateVersion = config.configuration.stateVersion;
}
