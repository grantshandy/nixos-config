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
      baseModule = { ... }: {
        documentation.nixos.enable = false;
        nix.extraOptions = ''
          	  experimental-features = nix-command flakes
          	'';
        system.stateVersion = "unstable";
      };
    in
    let
      homeModule = { ... }: {
        imports = [ home-manager.nixosModules.home-manager ];

        home-manager.useGlobalPkgs = true;
        home-manager.useUserPackages = true;

        home-manager.users.grant = import ./home.nix;
        home-manager.extraSpecialArgs = { inherit username; };
      };
    in
    {
      nixosConfigurations.wsl = nixpkgs.lib.nixosSystem {
        inherit system;
        modules = [
          baseModule
          nixos-wsl.nixosModules.wsl
          vscode-server.nixosModules.default
          ({ lib, pkgs, config, ... }: {
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
          homeModule
        ];
      };

      formatter."${system}" = nixpkgs.legacyPackages."${system}".nixpkgs-fmt;
    };
}
