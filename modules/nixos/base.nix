{
  pkgs,
  config,
  inputs,
  ...
}: {
  imports = [
    ./network-base.nix
    ./build-cluster.nix
    ./slskd-notify.nix
  ];

  i18n = let
    lc = "en_US.UTF-8";
  in {
    defaultLocale = lc;
    extraLocaleSettings.LC_ALL = lc;
  };

  nixpkgs.config.allowUnfree = true;
  nix.settings = {
    trusted-users = [config.identity.user.name];
    experimental-features = [
      "nix-command"
      "flakes"
      "pipe-operators"
    ];
    auto-optimise-store = true;
  };
  nix.registry = {
    nixpkgs.flake = inputs.nixpkgs;
    nixpkgs-unstable.flake = inputs.nixpkgs-unstable;
  };
  documentation.nixos.enable = false;

  users.users."${config.identity.user.name}" = {
    isNormalUser = true;
    description = config.identity.user.description;
    extraGroups = [
      "networkmanager"
      "wheel"
    ];
    packages = with pkgs; [git btop vim];
    openssh.authorizedKeys.keys = config.identity.ssh.userKeys;
  };

  security.sudo.extraRules = [
    {
      users = [config.identity.user.name];
      commands = [
        {
          command = "ALL";
          options = ["NOPASSWD"];
        }
      ];
    }
  ];

  system.stateVersion = config.configuration.stateVersion;
}
