{pkgs, ...}: {
  environment.systemPackages = with pkgs; [
    bazaar
    flatpak-builder
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
