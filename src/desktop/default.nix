# Good minimal GNOME configuration with the core programs
{
  pkgs,
  pkgs-unstable,
  lib,
  userConfig,
  ...
}: {
  imports = [
    ./wallpapers

    # ./sync.nix
    ./ko.nix
    ./firefox
    ./zed
  ];

  services.openssh = {
    enable = true;
    ports = [4321];
  };

  programs.steam.enable = true;

  # Enable the desktop environment and display manager
  services.displayManager.gdm.enable = true;
  services.desktopManager.gnome.enable = true;

  services.gnome.core-developer-tools.enable = true;
  services.flatpak = {
    enable = true;
    remotes = [
      {
        name = "flathub";
        location = "https://dl.flathub.org/repo/flathub.flatpakrepo";
      }
    ];
  };

  # exclude unused default programs and add modern fonts/core applications
  environment.gnome.excludePackages = with pkgs; [
    epiphany
    gnome-calendar
    gnome-console
    gnome-contacts
    gnome-maps
    gnome-music
    gnome-system-monitor
    gnome-software
    gnome-tour
    gnome-connections
    geary
    simple-scan
    snapshot
    yelp
    seahorse
  ];
  environment.systemPackages = with pkgs; [
    ptyxis
    resources
    eyedropper
    flatpak-builder
    bazaar
  ];
  fonts.packages = with pkgs; [
    noto-fonts
    noto-fonts-cjk-sans
    nerd-fonts.adwaita-mono
  ];

  services.gnome.evolution-data-server.enable = lib.mkForce false;
  services.gnome.gnome-online-accounts.enable = false;

  # Various backend desktop services
  boot.plymouth.enable = true;
  networking.networkmanager.enable = true;
  services.printing.enable = true;
  security.rtkit.enable = true;
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
  };

  services.orca.enable = lib.mkForce false;
  services.speechd.enable = lib.mkForce false;

  # use automatic timezone from GNOME
  time.timeZone = lib.mkForce null;

  services.gnome-korean-ime.enable = true;

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
        # "org/gnome/desktop/datetime".automatic-timezone = true;
        "org/gnome/system/location".enabled = true;

        # vv personal preferences vv
        "org/gnome/desktop/interface" = {
          color-scheme = "prefer-dark";
          clock-format = "12h";
          enable-hot-corners = true;
        };

        "org/gnome/desktop/background" = {
          color-shading-type = "solid";
          picture-options = "spanned";
        };

        # simplified alt-tabbing and workspaces
        "org/gnome/desktop/wm/keybindings" = {
          always-on-top = ["<Shift><Super>T"];
          switch-applications = [];
          switch-applications-backward = [];
          switch-windows = ["<Alt>Tab"];
          switch-windows-backward = ["<Shift><Alt>Tab"];
          switch-to-workspace-right = ["<Super>Tab"];
          switch-to-workspace-left = ["<Shift><Super>Tab"];
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
          ]
          ++ (userConfig.apps.favorites or []);
      };

      home.packages =
        (map (app: pkgs.${app}) (userConfig.apps.pkgs or []))
        ++ (map (app: pkgs-unstable.${app}) (userConfig.apps.pkgs-unstable or []));

      # Remove annoying printing configuration desktop entry
      xdg.desktopEntries."cups" = {
        name = "cups";
        noDisplay = true;
      };
    }

    # automatically enable this list of extensions
    (
      let
        extensions = with pkgs-unstable.gnomeExtensions; [
          blur-my-shell # make overview background blurred background image. Very nice.
          rounded-window-corners-reborn # rounded windows on firefox & vscode (performance cost)
          pip-on-top
        ];
      in {
        home.packages = extensions;
        dconf.settings = {
          "org/gnome/shell" = {
            disable-user-extensions = false;
            enabled-extensions = pkgs.lib.lists.forEach extensions (ext: ext.passthru.extensionUuid);
          };

          "org/gnome/shell/extensions/blur-my-shell/panel".override-background-dynamically = true;
          "org/gnome/shell/extensions/pip-on-top".stick = true;
        };
      }
    )
  ];
}
