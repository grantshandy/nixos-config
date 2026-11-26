# Home Manager itself, plus the profile skeleton for the primary user.
#
# There is no `sharedModules` list here: aspect pairing in
# modules/flake/assemble.nix supplies the Home Manager half of every aspect the
# host is enrolled in, which is what the old hand-written list did by hand.
{
  config,
  inputs,
  ...
}: {
  fleet.aspects.home-manager.hosts =
    config.fleet.hosts
    |> builtins.attrNames
    |> builtins.filter (name: config.fleet.hosts.${name}.homeManager.enable);

  flake.modules.nixos.home-manager = {
    config,
    pkgs-unstable,
    ...
  }: {
    imports = [inputs.home-manager.nixosModules.home-manager];

    home-manager = {
      useGlobalPkgs = true;
      useUserPackages = true;
      extraSpecialArgs = {inherit inputs pkgs-unstable;};

      users.${config.identity.user.name} = {
        home.username = config.identity.user.name;
        home.homeDirectory = "/home/${config.identity.user.name}";
        home.stateVersion = config.configuration.stateVersion;
      };
    };
  };
}
