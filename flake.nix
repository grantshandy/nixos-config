{
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-24.11";
    home-manager = {
      url = "github:nix-community/home-manager/release-24.11";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    firefox-addons = {
      url = "gitlab:rycee/nur-expressions?dir=pkgs/firefox-addons";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    inputs@{
      nixpkgs,
      home-manager,
      nur,
      ...
    }:
    let
      userConfig = builtins.readFile ./config.toml |> builtins.fromTOML;
      system = userConfig.system;
      specialArgs = {
        inherit userConfig inputs;
        stateVersion = "24.11";
      };
      base = [
        home-manager.nixosModules.home-manager
        nur.modules.nixos.default
        ./src/base.nix
        ./src/home.nix
      ];
      desktop = base ++ [ ./src/desktop.nix ];
    in
    {
      nixosConfigurations = {
        lenovo = nixpkgs.lib.nixosSystem {
          inherit system specialArgs;
          modules = desktop ++ [ ./hardware-configuration/lenovo.nix ];
        };

        xenon = nixpkgs.lib.nixosSystem {
          inherit system specialArgs;
          modules = desktop ++ [ ./hardware-configuration/xenon.nix ];
        };
      };

      formatter.${system} = nixpkgs.legacyPackages.${system}.nixfmt-rfc-style;
    };
}
