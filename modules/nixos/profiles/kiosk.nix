{
  config,
  lib,
  ...
}: {
  # Kiosks do not need the accessibility, discovery, or desktop audio services
  # enabled by general graphical defaults. QEMU talks to ALSA directly.
  services = {
    speechd.enable = lib.mkForce false;
    orca.enable = lib.mkForce false;
    pipewire.enable = lib.mkForce false;
    avahi = {
      enable = lib.mkForce false;
      nssmdns4 = lib.mkForce false;
      openFirewall = lib.mkForce false;
      publish.enable = lib.mkForce false;
    };
  };
  services.pulseaudio.enable = lib.mkForce false;

  fonts.enableDefaultPackages = false;
  xdg = {
    autostart.enable = lib.mkForce false;
    icons.enable = lib.mkForce false;
    mime.enable = lib.mkForce false;
    sounds.enable = lib.mkForce false;
  };

  # Keep the current generation plus one known-good rollback while the kiosk
  # profile is being validated.
  boot.loader.systemd-boot.configurationLimit = lib.mkForce 2;

  # Keep the administrative account and SSH access, but not workstation tools.
  users.users.${config.identity.user.name}.packages = lib.mkForce [];

  # Deployments use the repository's locked inputs, so interactive flake
  # registries only retain otherwise-unneeded nixpkgs source trees.
  nix = {
    registry = lib.mkForce {};
    gc = {
      automatic = true;
      dates = "daily";
      options = "--delete-older-than 3d";
    };
    settings = {
      min-free = 1024 * 1024 * 1024;
      max-free = 3 * 1024 * 1024 * 1024;
    };
  };
}
