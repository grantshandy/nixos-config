# A simplified GNOME desktop with nice things

{ pkgs, ... }:
let
  extensions = with pkgs.gnomeExtensions; [
    blur-my-shell
    (pkgs.callPackage ./rounded-window-corners.nix { })
  ];
in
{
  # Enable networking
  networking.networkmanager.enable = true;

  # Enable the xserver systems, GNOME, and gdm.
  services.xserver = {
    enable = true;
    excludePackages = [ pkgs.xterm ];
    xkb = {
      layout = "us";
      variant = "";
    };
    desktopManager = {
      xterm.enable = false;
      gnome.enable = true;
    };
    displayManager.gdm.enable = true;
  };

  # remove unnecessary applications from GNOME and add nicer ones
  environment.gnome.excludePackages =
    with pkgs; [ gnome-tour gnome-connections ]
      ++ (with gnome; [ gnome-music geary gnome-contacts gnome-calendar gnome-maps yelp totem ]);
  environment.systemPackages = [ pkgs.clapper ];

  # add nice fonts for compatibility
  fonts.packages = with pkgs; [ noto-fonts noto-fonts-cjk ];

  # Enable CUPS to print documents, and disable ugly web interface.
  services.printing = {
    enable = true;
    # webInterface = false;
  };

  # Enable sound with pipewire and pulseaudio.
  sound.enable = true;
  hardware.pulseaudio.enable = false;
  security.rtkit.enable = true;
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
  };

  home-manager.sharedModules = [{
    gtk = {
      enable = true;
      theme = {
        name = "adw-gtk3-dark";
        package = pkgs.adw-gtk3;
      };
      gtk3.extraConfig.Settings = "gtk-application-prefer-dark-theme=1";
      gtk4.extraConfig.Settings = "gtk-application-prefer-dark-theme=1";
      iconTheme = {
        name = "MoreWaita";
        package = pkgs.morewaita-icon-theme;
      };
    };

    # GNOME Shell Settings
    dconf.settings = {
      # dark theme
      "org/gnome/desktop/interface" = {
        color-scheme = "prefer-dark";
        enable-hot-corners = true;
      };

      # fewer workspaces (simpler), and American 12hr clock
      "org/gnome/mutter".dynamic-workspaces = true;
      "org/gtk/settings/file-chooser".clock-format = "12h";

      # simplified alt-tabbing
      "org/gnome/desktop/wm/keybindings" = {
        switch-applications = [ ];
        switch-applications-backward = [ ];
        switch-windows = [ "<Alt>Tab" ];
        switch-windows-backward = [ "<Shift><Alt>Tab" ];
      };
      "org/gnome/shell/window-switcher".current-workspace-only = false;
    };

    # automatically enable all `extensions`
    home.packages = extensions;
    dconf.settings."org/gnome/shell" = {
      disable-user-extensions = false;
      enabled-extensions = pkgs.lib.lists.forEach extensions (ext: ext.passthru.extensionUuid); # (soy face)
    };

    dconf.settings."org/gnome/shell/extensions/blur-my-shell/panel".override-background-dynamically = true;
  }];
}
