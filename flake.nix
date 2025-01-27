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
    background = {
      url = "https://images.wallpaperscraft.com/image/single/lake_mountains_landscape_1231510_1920x1080.jpg";
      flake = false;
    };
    proton-mail = {
      url = "https://raw.githubusercontent.com/ProtonMail/WebClients/2dac2f08a7969fe16160b22defb8392c20ef48a0/applications/mail/src/favicon.svg";
      flake = false;
    };
    proton-calendar = {
      url = "https://raw.githubusercontent.com/ProtonMail/WebClients/2dac2f08a7969fe16160b22defb8392c20ef48a0/applications/calendar/src/favicon.svg";
      flake = false;
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
