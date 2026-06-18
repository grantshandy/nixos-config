{pkgs, ...}: {
  imports = [
    ./gnome
    ./flatpak.nix
  ];

  home-manager.sharedModules = [
    ./firefox
    ./zed

    ./beeper.nix
    ./tools.nix
  ];

  environment.systemPackages = [
    pkgs.proton-vpn
    # pkgs.chromium
    # pkgs.libreoffice
  ];

  # virtualisation.docker.enable = true;
  # users.users.grant.extraGroups = ["docker"];

  # services.ollama = {
  # enable = true;
  # package = pkgs.ollama-rocm;
  # };

  # services.gnome.core-developer-tools.enable = true;
  #
  # virtualisation.virtualbox.host.enable = true;
  # users.extraGroups.vboxusers.members = ["grant"];

  # Non-free Extension Pack
  # nixpkgs.config.allowUnfree = true;
  # virtualisation.virtualbox.host.enableExtensionPack = true;

  # services.openssh = {
  #   enable = true;
  #   ports = [4321];
  #   settings = {
  #     PasswordAuthentication = true;
  #     PermitRootLogin = "no";
  #   };
  # };
  # networking.firewall.allowedTCPPorts = [4321];

  # programs.steam.enable = true;
}
