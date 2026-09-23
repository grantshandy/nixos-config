{
  pkgs,
  config,
  ...
}: {
  i18n = let
    lc = "en_US.UTF-8";
  in {
    defaultLocale = lc;
    extraLocaleSettings.LC_ALL = lc;
  };

  nixpkgs.config.allowUnfree = true;
  nix.settings = {
    experimental-features = [
      "nix-command"
      "flakes"
      "pipe-operators"
    ];
    auto-optimise-store = true;
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

  system.stateVersion = config.identity.stateVersion;
}
