# Good minimal GNOME configuration with the core programs
{
  pkgs,
  lib,
  userConfig,
  ...
}: {
  imports = [
    ./sync.nix
    ./ko.nix
    ./firefox
    ./zed
  ];

  # Enable the desktop environment and display manager
  services.xserver = {
    enable = true;

    displayManager.gdm.enable = true;
    desktopManager.gnome.enable = true;
    excludePackages = [pkgs.xterm];

    xkb = {
      layout = "us";
      variant = "";
    };
  };

  # exclude unused default programs and add modern fonts/core applications
  environment.gnome.excludePackages = with pkgs; [
    gnome-console
    snapshot
    gnome-tour
    gnome-connections
    yelp
    totem
    geary
    epiphany
    baobab
    gnome-music
    gnome-contacts
    gnome-calendar
    gnome-maps
    simple-scan
    gnome-software
    evince
    decibels
  ];
  environment.systemPackages = with pkgs; [
    celluloid
    ptyxis
    papers
  ];
  fonts.packages = with pkgs; [
    noto-fonts
    noto-fonts-cjk-sans
    nerd-fonts.adwaita-mono
  ];

  # Various backend desktop services
  boot.plymouth.enable = true;
  networking.networkmanager.enable = true;
  services.printing.enable = true;
  services.pulseaudio.enable = false;
  security.rtkit.enable = true;
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
  };

  services.orca.enable = false;
  services.speechd.enable = false;

  # use automatic timezone from GNOME
  time.timeZone = lib.mkForce null;

  # set GDM profile photo
  system.activationScripts.script.text = let
    name = userConfig.user.name;
    face = "cat.jpg";
  in ''
    mkdir -p /var/lib/AccountsService/users
    echo -e "[User]\nIcon=${pkgs.gnome-control-center}/share/pixmaps/faces/${face}\n" > /var/lib/AccountsService/users/${name}
    chown root:root /var/lib/AccountsService/users/${name}
    chmod 0600 /var/lib/AccountsService/users/${name}
  '';

  home-manager.sharedModules = [
    # desktop environment stylized
    {
      # style older gtk3/qt applications and non-gnome
      # application icons to look more like gtk4/adwaita:
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
      qt.platformTheme.name = "gtk3";

      # Some gnome settings that I prefer. Not too controversial.
      dconf.settings = {
        # enable automatic timezone and location services
        "org/gnome/desktop/datetime".automatic-timezone = true;
        "org/gnome/system/location".enabled = true;

        # vv personal preferences vv
        "org/gnome/desktop/interface" = {
          color-scheme = "prefer-dark";
          clock-format = "12h";
          enable-hot-corners = true;
        };

        "org/gnome/desktop/background" = {
          color-shading-type = "solid";
          picture-options = "zoom";
          picture-uri = "${./background.jpg}";
          picture-uri-dark = "${./background.jpg}";
        };

        # simplified alt-tabbing and workspaces
        "org/gnome/desktop/wm/keybindings" = {
          always-on-top = ["<Shift><Super>T"];
          switch-applications = [];
          switch-applications-backward = [];
          switch-windows = ["<Alt>Tab"];
          switch-windows-backward = ["<Shift><Alt>Tab"];
          switch-to-workspace-down = ["<Super>Tab"];
          switch-to-workspace-up = ["<Shift><Super>Tab"];
        };
        "org/gnome/shell/window-switcher".current-workspace-only = false;
        "org/gnome/mutter" = {
          dynamic-workspaces = true;
          edge-tiling = true;
        };

        "org/gnome/shell".favorite-apps =
          [
            "org.gnome.Nautilus.desktop"
            "org.gnome.Ptyxis.desktop"
            "firefox.desktop"
            "code.desktop"
          ]
          ++ (userConfig.apps.favorites or []);
      };

      home.packages = (userConfig.apps.pkgs or []) |> map (app: pkgs.${app});
    }

    # automatically enable this list of extensions
    (
      let
        extensions = with pkgs.gnomeExtensions; [
          # blur-my-shell # make overview background blurred background image. Very nice.
          # rounded-window-corners-reborn # rounded windows on firefox & vscode (performance cost)
        ];
      in {
        home.packages = extensions;
        dconf.settings = {
          "org/gnome/shell" = {
            disable-user-extensions = false;
            enabled-extensions = pkgs.lib.lists.forEach extensions (ext: ext.passthru.extensionUuid);
          };

          # "org/gnome/shell/extensions/blur-my-shell/panel".override-background-dynamically = true;
        };
      }
    )
  ];
}
