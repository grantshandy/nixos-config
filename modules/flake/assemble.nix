# Turns the fleet registry into nixosConfigurations and a Colmena hive.
#
# The only interesting part is aspect resolution: a host collects aspect names
# from three places, and each name is then looked up in *every* module class.
# One name therefore pulls in both the NixOS and the Home Manager half of a
# feature, which is why no feature file needs home-manager.sharedModules.
{
  config,
  inputs,
  lib,
  ...
}: let
  fleet = config.fleet;

  byName = pred: fleet.aspects |> lib.filterAttrs pred |> lib.attrNames;

  aspectsFor = hostName: host:
    lib.unique (
      # Explicit opt-ins come first so list-valued options merge in a
      # predictable order.
      host.aspects
      # A host is always enrolled in the aspect bearing its own name, which is
      # where its hardware and genuinely host-specific settings live.
      ++ [hostName]
      ++ byName (_: aspect:
        aspect.default
        || lib.elem hostName aspect.hosts
        || lib.intersectLists aspect.tags host.tags != [])
      # Declaring who runs a service is enough to place its implementation:
      # the aspect carrying it is the one named after the service.
      ++ (fleet.services
        |> lib.filterAttrs (_: service: service.host == hostName)
        |> lib.attrNames)
    );

  modulesOf = class: aspects: let
    available = config.flake.modules.${class} or {};
  in
    aspects
    |> lib.filter (aspect: available ? ${aspect})
    |> map (aspect: available.${aspect});

  reasonsFor = hostName: host: aspectName: let
    aspect = fleet.aspects.${aspectName} or null;
    matchingTags =
      if aspect == null
      then []
      else lib.intersectLists aspect.tags host.tags;
    hostedServices =
      fleet.services
      |> lib.filterAttrs (serviceName: service: serviceName == aspectName && service.host == hostName)
      |> lib.attrNames;
  in
    lib.optional (lib.elem aspectName host.aspects) "explicit"
    ++ lib.optional (aspectName == hostName) "host"
    ++ lib.optional (aspect != null && aspect.default) "default"
    ++ lib.optional (aspect != null && lib.elem hostName aspect.hosts) "host enrollment"
    ++ map (tag: "tag: ${tag}") matchingTags
    ++ map (service: "service: ${service}") hostedServices;

  moduleNamesFor = host: aspectName:
    config.flake.modules
    |> lib.filterAttrs (
      class: modules:
        modules ? ${aspectName}
        && (class != "homeManager" || host.homeManager.enable)
    )
    |> lib.attrNames
    |> map (class: "${class}.${aspectName}");

  debugFor = hostName: host: {
    inherit (host) system tags;
    aspects =
      aspectsFor hostName host
      |> map (name: {
        inherit name;
        reasons = reasonsFor hostName host name;
        modules = moduleNamesFor host name;
      });
  };

  pkgsUnstableFor = system:
    import inputs.nixpkgs-unstable {
      inherit system;
      config.allowUnfree = true;
    };

  specialArgsFor = host: {
    inherit inputs;
    pkgs-unstable = pkgsUnstableFor host.system;
  };

  modulesFor = name: let
    host = fleet.hosts.${name};
    aspects = aspectsFor name host;
    homeModules = modulesOf "homeManager" aspects;
  in
    [{networking.hostName = name;}]
    ++ lib.optional (host.homeManager.enable && homeModules != []) {
      home-manager.sharedModules = homeModules;
    }
    ++ modulesOf "nixos" aspects;

  mkHost = name: host:
    inputs.nixpkgs.lib.nixosSystem {
      inherit (host) system;
      specialArgs = specialArgsFor host;
      modules = modulesFor name;
    };

  mkColmenaNode = name: host:
    [
      ({config, ...}: {
        deployment = {
          targetHost =
            if host.ssh.targetHost == null
            then name
            else host.ssh.targetHost;
          targetPort = host.ssh.port;
          targetUser = config.identity.user.name;
          buildOnTarget = false;
        };
      })
    ]
    ++ modulesFor name;

  nixpkgsFor = system: import inputs.nixpkgs {inherit system;};
in {
  flake = {
    nixosConfigurations = lib.mapAttrs mkHost fleet.hosts;

    # Serializable explanation of the same aspect resolution used above. The
    # dev-shell's `fleet-tree` command renders this for troubleshooting.
    fleetDebug = lib.mapAttrs debugFor fleet.hosts;

    colmenaHive = inputs.colmena.lib.makeHive ({
        meta = {
          nixpkgs = nixpkgsFor "x86_64-linux";
          nodeNixpkgs = lib.mapAttrs (_: host: nixpkgsFor host.system) fleet.hosts;
          nodeSpecialArgs = lib.mapAttrs (_: specialArgsFor) fleet.hosts;
        };
      }
      // lib.mapAttrs mkColmenaNode fleet.hosts);
  };
}
