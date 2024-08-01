{
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { nixpkgs, home-manager, ... }:
    let username = "grant"; in
    let nameDescription = "Grant Handy"; in
    let stateVersion = "24.05"; in
    {
      nixosConfigurations.lenovo = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        modules = [
          home-manager.nixosModules.home-manager
          ({ pkgs, ... }: {
            # Bootloader & System.
            imports = [ ./hardware-configuration.nix ];

            boot.loader = {
              systemd-boot = {
                configurationLimit = 1;
                enable = true;
              };
              efi.canTouchEfiVariables = true;
            };

            # Set your time zone.
            time.timeZone = "America/Denver";

            # Select internationalisation properties.
            i18n = {
              defaultLocale = "en_US.UTF-8";
              supportedLocales = [ "en_US.UTF-8/UTF-8" "ko_KR.UTF-8/UTF-8" ];
              extraLocaleSettings = {
                LC_ADDRESS = "en_US.UTF-8";
                LC_IDENTIFICATION = "en_US.UTF-8";
                LC_MEASUREMENT = "en_US.UTF-8";
                LC_MONETARY = "en_US.UTF-8";
                LC_NAME = "en_US.UTF-8";
                LC_NUMERIC = "en_US.UTF-8";
                LC_PAPER = "en_US.UTF-8";
                LC_TELEPHONE = "en_US.UTF-8";
                LC_TIME = "en_US.UTF-8";
              };
            };

            nixpkgs.config.allowUnfree = true;
            nix.settings = {
              experimental-features = [ "nix-command" "flakes" ];
              auto-optimise-store = true;
            };
            documentation.nixos.enable = false;

            users.users."${username}" = {
              isNormalUser = true;
              description = nameDescription;
              extraGroups = [ "networkmanager" "wheel" ];
              packages = with pkgs; [ vim git helix ];
            };

            home-manager = {
              useGlobalPkgs = true;
              useUserPackages = true;
              users."${username}" = { ... }: {
                home.username = "${username}";
                home.homeDirectory = "/home/${username}";
                home.stateVersion = stateVersion;
              };
            };

            networking.hostName = "lenovo";
            system.stateVersion = stateVersion;
          })
          ./home.nix
          ./gnome.nix
          ./desktop.nix
        ];
      };

      formatter."x86_64-linux" = nixpkgs.legacyPackages."x86_64-linux".nixpkgs-fmt;
    };
}
