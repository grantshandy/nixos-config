{
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-25.05";
    home-manager = {
      url = "github:nix-community/home-manager/release-25.05";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    firefox-addons = {
      url = "gitlab:rycee/nur-expressions?dir=pkgs/firefox-addons";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nixvim = {
      url = "github:nix-community/nixvim/nixos-25.05";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = inputs @ {
    nixpkgs,
    home-manager,
    nixvim,
    ...
  }: let
    userConfig = builtins.readFile ./config.toml |> builtins.fromTOML;
    system = userConfig.system;

    stateVersion = "25.05";

    specialArgs = {
      inherit userConfig inputs;
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

      # time.timeZone = "America/Denver"; # <-- use auto timezone from GNOME instead
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

    mkSystem = hardware:
      nixpkgs.lib.nixosSystem {
        inherit system specialArgs;
        modules = [
          hardware
          baseConfiguration
          ./src/desktop
          home-manager.nixosModules.home-manager
          {
            home-manager = {
              useGlobalPkgs = true;
              useUserPackages = true;
              extraSpecialArgs = specialArgs;
              users.grant = {...}: {
                imports = [./src/home];

                home.username = "${userConfig.user.name}";
                home.homeDirectory = "/home/${userConfig.user.name}";
                home.stateVersion = stateVersion;
              };
            };
          }
        ];
      };
  in {
    nixosConfigurations = {
      lenovo = mkSystem ./hardware-configuration/lenovo.nix;
      xenon = mkSystem ./hardware-configuration/xenon.nix;
    };

    homeConfigurations.cade = home-manager.lib.homeManagerConfiguration {
      pkgs = nixpkgs.legacyPackages.${system};
      modules = [./src/home];
    };

    formatter.${system} = nixpkgs.legacyPackages.${system}.nixfmt-rfc-style;
  };
}
