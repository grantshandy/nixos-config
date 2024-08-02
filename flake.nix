{
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { nixpkgs, home-manager, ... }:
    let config = (builtins.fromTOML (builtins.readFile ./config.toml)); in
    let stateVersion = "24.11"; in
    let
      baseModule = { pkgs, ... }: {
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
        i18n = {
          defaultLocale = "en_US.UTF-8";
          extraLocaleSettings.LC_ALL = "en_US.UTF-8";
        };

        nixpkgs.config.allowUnfree = true;
        nix.settings = {
          experimental-features = [ "nix-command" "flakes" ];
          auto-optimise-store = true;
        };
        documentation.nixos.enable = false;

        users.users."${config.user.name}" = {
          isNormalUser = true;
          description = config.user.description;
          extraGroups = [ "networkmanager" "wheel" ];
          packages = with pkgs; [ vim git ];
        };

        home-manager = {
          useGlobalPkgs = true;
          useUserPackages = true;
          users."${config.user.name}" = { ... }: {
            home.username = "${config.user.name}";
            home.homeDirectory = "/home/${config.user.name}";
            home.stateVersion = stateVersion;
          };
        };

        networking.hostName = config.hostname;
        system.stateVersion = stateVersion;
      };
    in
    {
      nixosConfigurations."${config.hostname}" = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        modules = [
          ./hardware-configuration.nix
          home-manager.nixosModules.home-manager
          baseModule
          ./home.nix
          ./gnome.nix
          ./desktop.nix
          ./sync.nix
          ({ pkgs, ... }: import ./ko.nix { inherit home-manager pkgs; })
        ];
      };

      formatter."x86_64-linux" = nixpkgs.legacyPackages."x86_64-linux".nixpkgs-fmt;
    };
}
