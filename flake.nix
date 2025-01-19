{
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-24.11";
    home-manager = {
      url = "github:nix-community/home-manager/release-24.11";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nur = {
      url = "github:nix-community/NUR";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    background = {
      url = "https://images.wallpaperscraft.com/image/single/lake_mountains_landscape_1231510_1920x1080.jpg";
      flake = false;
    };
  };

  outputs =
    inputs@{ nixpkgs, home-manager, nur, ... }:
    let
      userConfig = builtins.fromTOML (builtins.readFile ./config.toml);
      system = userConfig.system;
      specialArgs = {
        inherit userConfig inputs;
        stateVersion = "24.11";
      };
    in
    {
      nixosConfigurations = {
        lenovo = nixpkgs.lib.nixosSystem {
          inherit system specialArgs;
          modules = [
            home-manager.nixosModules.home-manager
            nur.modules.nixos.default
            ./hardware-configuration/lenovo.nix
            ./src/base.nix
            ./src/home.nix
            ./src/desktop.nix
            ./src/ko.nix
            ./src/sync.nix
          ];
        };

        xenon = nixpkgs.lib.nixosSystem {
          inherit system specialArgs;
          modules = [
            home-manager.nixosModules.home-manager
            nur.modules.nixos.default
            ./hardware-configuration/xenon.nix
            ./src/base.nix
            ./src/home.nix
            ./src/desktop.nix
            ./src/ko.nix
            ./src/sync.nix
          ];
        };
      };

      formatter."${system}" = nixpkgs.legacyPackages."${system}".nixfmt-rfc-style;
    };
}
