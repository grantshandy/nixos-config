{inputs, ...}: {
  flake.nixosConfigurations = let
    hostsRegistry = import ../hosts/registry.nix;

    mkHost = name: hostMeta:
      inputs.nixpkgs.lib.nixosSystem {
        system = hostMeta.system;
        specialArgs = {
          inherit inputs;
          pkgs-unstable = import inputs.nixpkgs-unstable {
            system = hostMeta.system;
            config.allowUnfree = true;
          };
        };
        modules = [
          {
            networking.hostName = name;
            network.hosts = hostsRegistry;
          }
          ../modules/options.nix
          ../modules/nixos/base.nix
          ../modules/nixos/network-base.nix
          ../identity.nix
          inputs.home-manager.nixosModules.home-manager
          ../modules/home/home-manager-base.nix
          inputs.agenix.nixosModules.default
          ../hosts/${name}
        ];
      };
  in
    inputs.nixpkgs.lib.mapAttrs mkHost hostsRegistry;
}
