{
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-24.11";
    home-manager = {
      url = "github:nix-community/home-manager/release-24.11";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { nixpkgs, home-manager, ... }:
    let userConfig = (builtins.fromTOML (builtins.readFile ./config.toml)); in
    let stateVersion = "24.11"; in
    let
      baseModule = hostname: { pkgs, ... }: {
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
        i18n =
          let lc = "en_US.UTF-8"; in
          {
            defaultLocale = lc;
            extraLocaleSettings = {
              LC_ADDRESS = lc;
              LC_IDENTIFICATION = lc;
              LC_MEASUREMENT = lc;
              LC_MONETARY = lc;
              LC_NAME = lc;
              LC_NUMERIC = lc;
              LC_PAPER = lc;
              LC_TELEPHONE = lc;
              LC_TIME = lc;
            };
          };

        nixpkgs.config.allowUnfree = true;
        nix.settings = {
          experimental-features = [ "nix-command" "flakes" ];
          auto-optimise-store = true;
        };
        documentation.nixos.enable = false;

        users.users."${userConfig.user.name}" = {
          isNormalUser = true;
          description = userConfig.user.description;
          extraGroups = [ "networkmanager" "wheel" ];
          packages = with pkgs; [ helix git ];
        };

        home-manager = {
          useGlobalPkgs = true;
          # useUserPackages = true;
          users."${userConfig.user.name}" = { ... }: {
            home.username = "${userConfig.user.name}";
            home.homeDirectory = "/home/${userConfig.user.name}";
            home.stateVersion = stateVersion;
            programs.home-manager.enable = true;
          };
        };

        networking.hostName = hostname;
        system.stateVersion = stateVersion;
      };
      addImports = path: { pkgs, lib, ... }: import path { inherit pkgs lib userConfig home-manager; };
    in
    {
      nixosConfigurations.lenovo = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        modules = [
          ./hardware-configuration/lenovo.nix
          home-manager.nixosModules.home-manager
          (baseModule "lenovo")
          (addImports ./src/desktop.nix)
          (addImports ./src/gnome.nix)
          (addImports ./src/home.nix)
          (addImports ./src/ko.nix)
          (addImports ./src/sync.nix)
        ];
      };

      nixosConfigurations.xenon = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        modules = [
          ./hardware-configuration/xenon.nix
          home-manager.nixosModules.home-manager
          (baseModule "xenon")
          (addImports ./src/desktop.nix)
          (addImports ./src/gnome.nix)
          (addImports ./src/home.nix)
          (addImports ./src/ko.nix)
          (addImports ./src/sync.nix)
        ];
      };

      formatter."x86_64-linux" = nixpkgs.legacyPackages."x86_64-linux".nixpkgs-fmt;
    };
}
