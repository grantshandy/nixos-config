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
  };

  outputs = inputs@{ nixpkgs, home-manager, ... }:
    let
      userConfig = builtins.fromTOML (builtins.readFile ./config.toml);
      system = "x86_64-linux";
      specialArgs = {
        inherit userConfig system inputs;
        stateVersion = "24.11";
      };
    in
    {
      nixosConfigurations = {
        lenovo = nixpkgs.lib.nixosSystem {
          inherit system specialArgs;
          modules = [
            ({ ... }: { networking.hostName = "lenovo"; })
            home-manager.nixosModules.home-manager
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
            ({ ... }: { networking.hostName = "xenon"; })
            home-manager.nixosModules.home-manager
            ./hardware-configuration/xenon.nix
            ./src/base.nix
            ./src/home.nix
            ./src/desktop.nix
            ./src/ko.nix
            ./src/sync.nix
          ];
        };
      };

      formatter."${system}" = nixpkgs.legacyPackages."${system}".nixpkgs-fmt;
    };
}
