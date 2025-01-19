{ pkgs, lib, userConfig, stateVersion, ... }: {
  # minimal systemd-boot
  boot.loader = {
    systemd-boot = {
      # don't show old generations in the boot screen
      configurationLimit = 1;
      enable = true;
    };
    efi.canTouchEfiVariables = true;
  };

  # time.timeZone = "America/Denver"; # <-- use auto timezone from GNOME instead
  i18n =
    let lc = "en_US.UTF-8"; in
    {
      defaultLocale = lc;
      extraLocaleSettings = {
        LC_ADDRESS = lc;
        LC_IDENTIFICATION = lc;
        LC_MEASUREMENT = lc;
        LC_MONETARY = lc;
        LC_NAME = lc;
        LC_NUMERIC = lc;
        LC_PAPER = lc;
        LC_TELEPHONE = lc;
        LC_TIME = lc;
      };
    };

  nixpkgs.config.allowUnfree = true;
  nix.settings = {
    experimental-features = [ "nix-command" "flakes" ];
    auto-optimise-store = true;
  };
  documentation.nixos.enable = false;

  users.users."${userConfig.user.name}" = {
    isNormalUser = true;
    description = userConfig.user.description;
    extraGroups = [ "networkmanager" "wheel" ];
    packages = with pkgs; [ helix git ];
  };

  home-manager = {
    useGlobalPkgs = true;
    useUserPackages = true;
    users."${userConfig.user.name}" = { ... }: {
      home.username = "${userConfig.user.name}";
      home.homeDirectory = "/home/${userConfig.user.name}";
      home.stateVersion = stateVersion;
      programs.home-manager.enable = true;
    };
  };

  system.stateVersion = stateVersion;
}
