{
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-25.11";
    home-manager = {
      url = "github:nix-community/home-manager/release-25.11";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    firefox-addons = {
      url = "gitlab:rycee/nur-expressions?dir=pkgs/firefox-addons";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nix-flatpak.url = "github:gmodena/nix-flatpak/?ref=latest";
    nixpkgs-unstable.url = "github:nixos/nixpkgs";
  };

  outputs = inputs @ {
    nixpkgs,
    nixpkgs-unstable,
    home-manager,
    ...
  }: let
    userConfig = builtins.fromTOML (builtins.readFile ./config.toml);
    system = userConfig.system;

    stateVersion = "25.11";

    specialArgs = {
      inherit userConfig inputs;

      pkgs-unstable = import nixpkgs-unstable {
        inherit system;
        config.allowUnfree = true;
      };
    };

    baseConfiguration = {pkgs, ...}: {
      # minimal systemd-boot
      boot.loader = {
        systemd-boot = {
          # don't show old generations in the boot screen
          configurationLimit = 1;
          enable = true;
        };
        efi.canTouchEfiVariables = true;
      };

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

      users.users."${userConfig.user.name}" = {
        isNormalUser = true;
        description = userConfig.user.description;
        extraGroups = [
          "networkmanager"
          "wheel"
        ];
        packages = with pkgs; [git];
      };

      system.stateVersion = stateVersion;
    };

    homeConfiguration = {
      imports = [home-manager.nixosModules.home-manager];

      home-manager = {
        useGlobalPkgs = true;
        useUserPackages = true;
        extraSpecialArgs = specialArgs;
        users.${userConfig.user.name} = {...}: {
          home.username = "${userConfig.user.name}";
          home.homeDirectory = "/home/${userConfig.user.name}";
          home.stateVersion = stateVersion;
        };
      };
    };

    mkSystem = hardware:
      nixpkgs.lib.nixosSystem {
        inherit system specialArgs;

        modules = [
          hardware
          baseConfiguration
          homeConfiguration
          ./src
        ];
      };
  in {
    nixosConfigurations = {
      lenovo = mkSystem ./hardware-configuration/lenovo.nix;
      xenon = mkSystem ./hardware-configuration/xenon.nix;
    };
  };
}
