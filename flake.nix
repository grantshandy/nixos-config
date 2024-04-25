{
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    nixos-wsl = {
      url = "github:nix-community/NixOS-WSL";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    vscode-server = {
      url = "github:nix-community/nixos-vscode-server";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { nixpkgs, nixos-wsl, home-manager, vscode-server, ... }:
    let system = "x86_64-linux"; in
    let username = "grant"; in
    let
      baseModule = { pkgs, ... }: {
        imports = [ home-manager.nixosModules.home-manager ];

        # time zone and internationalization properties.
        time.timeZone = "America/Denver";
        i18n = {
          defaultLocale = "en_US.UTF-8";
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

        # nix settings
        nixpkgs.config.allowUnfree = true;
        documentation.nixos.enable = false;
        nix.settings = {
          experimental-features = [ "nix-command" "flakes" ];
          auto-optimise-store = true;
        };
        environment.systemPackages = with pkgs; [ git ];
        system.stateVersion = "24.05";

        users.users."${username}" = {
          isNormalUser = true;
          description = "Grant Handy";
          extraGroups = [ "networkmanager" "wheel" ];
        };

        home-manager.useGlobalPkgs = true;
        home-manager.useUserPackages = true;
        home-manager.extraSpecialArgs = { inherit username; };
      };
    in
    {
      nixosConfigurations = {
        # laptop
        lenovo = nixpkgs.lib.nixosSystem {
          inherit system;
          modules = [
            baseModule
            ./hardware-configuration.nix
            ./gnome-desktop.nix
            (import ./syncthing.nix { inherit username; })
            ({ ... }: {
              # Bootloader.
              boot.loader.systemd-boot.enable = true;
              boot.loader.efi.canTouchEfiVariables = true;

              networking.hostName = "lenovo";
              programs.fuse.userAllowOther = true;
              home-manager.users."${username}" = import ./home-desktop.nix;
            })
          ];
        };

        # windows subsystem for linux configuration
        wsl = nixpkgs.lib.nixosSystem {
          inherit system;
          modules = [
            baseModule
            nixos-wsl.nixosModules.wsl
            vscode-server.nixosModules.default
            ({ lib, pkgs, config, ... }: {
              home-manager.users."${username}" = import ./home-base.nix;

              services.vscode-server.enable = true;
              programs.nix-ld.enable = true;

              wsl = {
                enable = true;
                wslConf.automount.root = "/mnt";
                defaultUser = "${username}";
                startMenuLaunchers = true;
                useWindowsDriver = true;
                # patches for vscode server
                extraBin = with pkgs; [
                  { src = "${coreutils}/bin/uname"; }
                  { src = "${coreutils}/bin/dirname"; }
                  { src = "${coreutils}/bin/readlink"; }
                  { src = "${coreutils}/bin/cat"; }
                  { src = "${gnused}/bin/sed"; }
                ];
              };

              hardware.opengl.setLdLibraryPath = true;

              networking.hostName = "wsl";
              environment.systemPackages = [ pkgs.wget ];
            })
          ];
        };
      };

      formatter."${system}" = nixpkgs.legacyPackages."${system}".nixpkgs-fmt;
    };
}
