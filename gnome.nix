# Good minimal GNOME configuration with the core programs

{ pkgs, lib, ... }: {
  # Enable the X11 windowing system.
  services.xserver = {
    enable = true;

    displayManager.gdm.enable = true;
    desktopManager.gnome.enable = true;

    xkb = {
      layout = "us";
      variant = "";
    };
  };

  environment.gnome.excludePackages =
    with pkgs; [ gnome-tour gnome-connections yelp totem geary gnome-calendar ]
      ++ (with gnome; [ gnome-music gnome-contacts gnome-maps ]);
  environment.systemPackages = [ pkgs.clapper ];

  fonts.packages = with pkgs; [ noto-fonts noto-fonts-cjk-sans ];

  # Various services
  networking.networkmanager.enable = true;
  services.printing.enable = true;

  hardware.pulseaudio.enable = false;
  security.rtkit.enable = true;
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
  };

  # use automatic timezone
  time.timeZone = lib.mkForce null;

  home-manager.sharedModules =
    let
      extensions = with pkgs.gnomeExtensions; [
        blur-my-shell
        rounded-window-corners-reborn
      ];
    in
    [{
      gtk = {
        enable = true;
        theme = {
          name = "adw-gtk3-dark";
          package = pkgs.adw-gtk3;
        };
        iconTheme = {
          name = "MoreWaita";
          package = pkgs.morewaita-icon-theme;
        };
      };

      # GNOME Shell Settings
      dconf.settings = {
        "org/gnome/desktop/interface" = {
          color-scheme = "prefer-dark";
          clock-format = "12h";
          enable-hot-corners = true;
        };

        "org/gnome/mutter".dynamic-workspaces = true;

        # automatic timezone
        "org/gnome/desktop/datetime".automatic-timezone = true;
        "org/gnome/system/location".enabled = true;

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
