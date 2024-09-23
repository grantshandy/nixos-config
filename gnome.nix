# Good minimal GNOME configuration with the core programs

{ pkgs, lib, ... }: {
  # Enable the desktop environment and manager
  services.xserver = {
    enable = true;

    displayManager.gdm.enable = true;
    desktopManager.gnome.enable = true;
    excludePackages = [ pkgs.xterm ];

    xkb = {
      layout = "us";
      variant = "";
    };
  };

  # exclude unused default programs and add modern fonts/core applications
  environment.gnome.excludePackages =
    with pkgs; [ gnome-tour gnome-connections yelp totem geary gnome-calendar epiphany baobab gnome-music gnome-contacts gnome-maps simple-scan ];
  environment.systemPackages = [ pkgs.clapper ];
  fonts.packages = with pkgs; [ noto-fonts noto-fonts-cjk-sans iosevka ];

  # Various desktop services
  boot.plymouth.enable = true;
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

  # use automatic timezone from GNOME
  time.timeZone = lib.mkForce null;

  home-manager.sharedModules =
    [
      {
        # force non-gnome apps in line
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

        dconf.settings = {
          # enable automatic timezone and location services
          "org/gnome/desktop/datetime".automatic-timezone = true;
          "org/gnome/system/location".enabled = true;

          # vv personal preferences vv
          "org/gnome/desktop/interface" = {
            color-scheme = "prefer-dark";
            clock-format = "12h";
            enable-hot-corners = true;
            monospace-font-name = "Iosevka 12";
          };

          "org/gnome/desktop/background" =
            let bgDir = "file://${pkgs.gnome-backgrounds}/share/backgrounds/gnome"; in
            {
              color-shading-type = "solid";
              picture-options = "zoom";
              picture-uri = "${bgDir}/amber-l.jxl";
              picture-uri-dark = "${bgDir}/amber-d.jxl";
              primary-color = "#ff7800";
              secondary-color = "#000000";
            };

          # simplified alt-tabbing and workspaces
          "org/gnome/desktop/wm/keybindings" = {
            switch-applications = [ ];
            switch-applications-backward = [ ];
            switch-windows = [ "<Alt>Tab" ];
            switch-windows-backward = [ "<Shift><Alt>Tab" ];
          };
          "org/gnome/shell/window-switcher".current-workspace-only = false;
          "org/gnome/mutter" = {
            dynamic-workspaces = true;
            edge-tiling = true;
          };
        };
      }

      # minimal cosmetic extensions
      (
        let
          extensions = with pkgs.gnomeExtensions; [
            blur-my-shell
            # rounded-window-corners-reborn
          ];
        in
        {
          home.packages = extensions;
          dconf.settings = {
            "org/gnome/shell" = {
              disable-user-extensions = false;
              enabled-extensions = pkgs.lib.lists.forEach extensions (ext: ext.passthru.extensionUuid); # (compsci soy face)
            };

            "org/gnome/shell/extensions/blur-my-shell/panel".override-background-dynamically = true;
          };
        }
      )
    ];
}
