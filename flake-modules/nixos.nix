{inputs, ...}: let
  lib = inputs.nixpkgs.lib;
  hostsRegistry = import ../hosts/registry.nix;

  nixpkgsFor = system:
    import inputs.nixpkgs {
      inherit system;
    };

  specialArgsFor = hostMeta: {
    inherit inputs;
    pkgs-unstable = import inputs.nixpkgs-unstable {
      system = hostMeta.system;
      config.allowUnfree = true;
    };
  };

  modulesFor = name: [
    {
      networking.hostName = name;
      network.hosts = hostsRegistry;
    }
    ../modules/options.nix
    inputs.self.nixosModules.stateVersion
    ../modules/nixos/base.nix
    ../identity.nix
    inputs.home-manager.nixosModules.home-manager
    ../modules/home/home-manager-base.nix
    inputs.agenix.nixosModules.default
    ../hosts/${name}
  ];

  mkHost = name: hostMeta:
    lib.nixosSystem {
      system = hostMeta.system;
      specialArgs = specialArgsFor hostMeta;
      modules = modulesFor name;
    };

  mkColmenaNode = name: hostMeta:
    [
      ({config, ...}: {
        deployment = {
          targetHost = name;
          targetPort = hostMeta.ssh.port;
          targetUser = config.identity.user.name;
          buildOnTarget = hostMeta.deployment.buildOnTarget or true;
        };
      })
    ]
    ++ modulesFor name;
in {
  flake = {
    nixosConfigurations = lib.mapAttrs mkHost hostsRegistry;

    colmenaHive = inputs.colmena.lib.makeHive ({
        meta = {
          nixpkgs = nixpkgsFor "x86_64-linux";
          nodeNixpkgs = lib.mapAttrs (_: hostMeta: nixpkgsFor hostMeta.system) hostsRegistry;
          nodeSpecialArgs = lib.mapAttrs (_: hostMeta: specialArgsFor hostMeta) hostsRegistry;
        };
      }
      // lib.mapAttrs mkColmenaNode hostsRegistry);
  };
}
