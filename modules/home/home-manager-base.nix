{
  config,
  inputs,
  pkgs-unstable,
  ...
}: {
  home-manager = {
    useGlobalPkgs = true;
    useUserPackages = true;
    extraSpecialArgs = {inherit inputs pkgs-unstable;};

    sharedModules = [
      ../options.nix
      ../../identity.nix
      ./base.nix
    ];

    users.${config.identity.user.name} = {
      home.username = config.identity.user.name;
      home.homeDirectory = "/home/${config.identity.user.name}";
      home.stateVersion = config.identity.stateVersion;
    };
  };
}
