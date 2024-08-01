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
    let stateVersion = "24.11"; in
    let hostName = "lenovo"; in
    {
      nixosConfigurations."${hostName}" = nixpkgs.lib.nixosSystem {
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

            # time.timeZone = "America/Denver"; # <-- use auto timezone from GNOME
            i18n =
              let mainLocale = "en_US.UTF-8"; in
              {
                defaultLocale = mainLocale;
                extraLocaleSettings = {
                  LC_ADDRESS = mainLocale;
                  LC_IDENTIFICATION = mainLocale;
                  LC_MEASUREMENT = mainLocale;
                  LC_MONETARY = mainLocale;
                  LC_NAME = mainLocale;
                  LC_NUMERIC = mainLocale;
                  LC_PAPER = mainLocale;
                  LC_TELEPHONE = mainLocale;
                  LC_TIME = mainLocale;
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

            networking.hostName = hostName;
            system.stateVersion = stateVersion;
          })
          ./home.nix
          ./gnome.nix
          ./desktop.nix
          ({ pkgs, ... }: import ./sync.nix { inherit username pkgs; })
          ({ pkgs, ... }: import ./ko.nix { inherit home-manager pkgs; })
        ];
      };

      formatter."x86_64-linux" = nixpkgs.legacyPackages."x86_64-linux".nixpkgs-fmt;
    };
}
