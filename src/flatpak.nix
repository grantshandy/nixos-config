{
  pkgs,
  pkgs-unstable,
  ...
}: {
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
    ];
  };
}
