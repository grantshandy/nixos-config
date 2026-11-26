{inputs, ...}: {
  fleet.aspects.flatpak.tags = ["desktop"];

  flake.modules.nixos.flatpak = {
    pkgs,
    pkgs-unstable,
    ...
  }: {
    imports = [inputs.nix-flatpak.nixosModules.nix-flatpak];

    environment.systemPackages = [
      pkgs-unstable.bazaar
      pkgs.flatpak-builder
    ];

    services.flatpak = {
      enable = true;
      remotes = [
        {
          name = "flathub";
          location = "https://dl.flathub.org/repo/flathub.flatpakrepo";
        }
        {
          name = "gnome-nightly";
          location = "https://nightly.gnome.org/gnome-nightly.flatpakrepo";
        }
      ];
    };
  };
}
