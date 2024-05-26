{
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    wsl = {
      url = "github:nix-community/nixos-wsl";
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
    hardware.url = "github:NixOS/nixos-hardware/master";
  };

  outputs = { nixpkgs, wsl, home-manager, vscode-server, hardware, ... }:
    let username = "grant"; in
    let nameDescription = "Grant Handy"; in
    let homeDirectory = "/home/${username}"; in
    let stateVersion = "24.05"; in
    let
      baseModule = { pkgs, ... }: {
        imports = [
          home-manager.nixosModules.home-manager
        ];

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
        nix.settings = {
          experimental-features = [ "nix-command" "flakes" ];
          auto-optimise-store = true;
        };
        environment.systemPackages = with pkgs; [ git vim ];
        documentation.nixos.enable = false;
        programs.command-not-found.enable = false;
        system.stateVersion = stateVersion;

        users.users."${username}" = {
          isNormalUser = true;
          description = nameDescription;
          extraGroups = [ "networkmanager" "wheel" ];
        };

        home-manager.useGlobalPkgs = true;
        home-manager.useUserPackages = true;
        home-manager.users."${username}" = { ... }: {
          home.username = "${username}";
          home.homeDirectory = "${homeDirectory}";
          home.stateVersion = stateVersion;
        };
      };
    in
    rec {
      # laptop
      # nixosConfigurations.lenovo = nixpkgs.lib.nixosSystem {
      #   inherit system;
      #   modules = [
      #     baseModule

      #     ./hardware-configuration.nix
      #     ./gnome.nix

      #     ./home.nix
      #     ./desktop.nix

      #     ({ ... }: {
      #       # Bootloader.
      #       boot.loader.systemd-boot.enable = true;
      #       boot.loader.efi.canTouchEfiVariables = true;
      #       # Avoid touchpad click to tap (clickpad) bug on lenovo laptops.
      #       boot.kernelParams = [ "psmouse.synaptics_intertouch=0" ];

      #       networking.hostName = "lenovo";
      #       programs.fuse.userAllowOther = true;
      #     })
      #   ];
      # };

      # windows subsystem for linux configuration
      nixosConfigurations.wsl = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        modules = [
          baseModule
          ./home.nix
          wsl.nixosModules.wsl
          vscode-server.nixosModules.default
          ({ pkgs, ... }: {
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
            # boot.binfmt.emulatedSystems = [ "aarch64-linux" ];
            environment.systemPackages = [ pkgs.wget ];
          })
        ];
      };

      nixosConfigurations.rpi = nixpkgs.lib.nixosSystem {
        system = "aarch64-linux";
        modules = [
          "${nixpkgs}/nixos/modules/installer/sd-card/sd-image-aarch64.nix"
          hardware.nixosModules.raspberry-pi-4
          baseModule
          ./home.nix
          # ./hardware-rpi.nix
          ({ pkgs, ... }: {
            nixpkgs.config.allowUnsupportedSystem = true;
            nixpkgs.hostPlatform.system = "aarch64-linux";
            nixpkgs.buildPlatform.system = "x86_64-linux"; #If you build on x86 other wise changes this.
          
            # enable V3D opengl renderer
            hardware = {
              raspberry-pi."4" = {
                apply-overlays-dtmerge.enable = true;
                fkms-3d.enable = true;
              };
            };

            networking.hostName = "rpi";

            services.xserver = {
              enable = true;
              displayManager.lightdm.enable = true;
              desktopManager.xfce.enable = true;
            };
          })
        ];
      };
      packages."x86_64-linux".rpi = nixosConfigurations.rpi.config.system.build.sdImage;

      formatter."x86_64-linux" = nixpkgs.legacyPackages."x86_64-linux".nixpkgs-fmt;
    };
}
