# Good minimal GNOME configuration with the core programs

{
  pkgs,
  lib,
  userConfig,
  inputs,
  ...
}:
{
  # Enable the desktop environment and display manager
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
  environment.gnome.excludePackages = with pkgs; [
    gnome-console
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
  ];
  environment.systemPackages = with pkgs; [
    clapper
    blackbox-terminal
  ];
  fonts.packages = with pkgs; [
    noto-fonts
    noto-fonts-cjk-sans
    iosevka
  ];

  # Various backend desktop services
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

  # set GDM profile photo
  system.activationScripts.script.text =
    let
      name = userConfig.user.name;
      face = "cat.jpg";
    in
    ''
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
          monospace-font-name = "Iosevka 12";
        };

        "org/gnome/desktop/background" = {
          color-shading-type = "solid";
          picture-options = "zoom";
          picture-uri = "${inputs.background}";
          picture-uri-dark = "${inputs.background}";
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

    # automatically enable this list of extensions
    (
      let
        extensions = with pkgs.gnomeExtensions; [
          blur-my-shell # make overview background blurred background image. Very nice.
          # rounded-window-corners-reborn # rounded windows on firefox & vscode (performance cost)
        ];
      in
      {
        home.packages = extensions;
        dconf.settings = {
          "org/gnome/shell" = {
            disable-user-extensions = false;
            # (functional compsci soy face):
            enabled-extensions = pkgs.lib.lists.forEach extensions (ext: ext.passthru.extensionUuid);
          };

          "org/gnome/shell/extensions/blur-my-shell/panel".override-background-dynamically = true;
        };
      }
    )

    # basic applications and vscode configuration
    {
      home.packages = with pkgs; [
        obsidian
        protonvpn-gui
        beeper
        anki
        prismlauncher
      ];

      dconf.settings."org/gnome/shell".favorite-apps = [
        "org.gnome.Nautilus.desktop"
        "org.gnome.Console.desktop"
        "firefox.desktop"
        "code.desktop"
        "com.raggesilver.BlackBox.desktop"
        "obsidian.desktop"
        "beeper.desktop"
      ];

      programs.vscode = {
        enable = true;
        package = pkgs.vscode-fhs;
        extensions = with pkgs.vscode-extensions; [
          rust-lang.rust-analyzer
          fill-labs.dependi
          tamasfe.even-better-toml
          jnoortheen.nix-ide
          mkhl.direnv
          usernamehw.errorlens
          bradlc.vscode-tailwindcss
          piousdeer.adwaita-theme
          wakatime.vscode-wakatime
        ];
        userSettings = {
          window = {
            # titleBarStyle = "custom";
            commandCenter = true;
            autoDetectColorScheme = true;
          };
          workbench = {
            preferredDarkColorTheme = "Adwaita Dark";
            preferredLightColorTheme = "Adwaita Light";
            productIconTheme = "adwaita";
            iconTheme = null;
            tree.indent = 12;
            colorTheme = "Adwaita Dark";
            startupEditor = "none";
            activityBar.location = "top";
          };
          editor = {
            quickSuggesions = {
              other = "on";
              comments = "on";
              strings = "on";
            };
            renderLineHighlight = "none";
            inlayHints.enabled = "offUnlessPressed";
          };
          files.simpleDialog.enable = true;

          "nix.enableLanguageServer" = true;
          "nix.serverPath" = "${pkgs.nixd}/bin/nixd";
        };
      };
    }

    # Custom web shortcuts in config.toml
    (
      let
        iconDir = "${pkgs.morewaita-icon-theme}/share/icons/MoreWaita/scalable/apps";
      in
      {
        xdg.desktopEntries =
          userConfig.shortcuts
          |> builtins.filter (
            s:
            (builtins.hasAttr "icon" s && s.icon != false)
            && (builtins.hasAttr "desktop" s && s.desktop == true)
          )
          |> builtins.map (shortcut: {
            name = lib.toLower (builtins.replaceStrings [ " " ] [ "" ] shortcut.name);
            value = {
              name = shortcut.name;
              icon =
                if builtins.typeOf shortcut.icon == "set" then
                  pkgs.fetchurl shortcut.icon
                else
                  "${iconDir}/${shortcut.icon}";
              terminal = false;
              exec = "xdg-open ${shortcut.url}";
            };
          })
          |> builtins.listToAttrs;
      }
    )

    # Firefox configuration
    (
      let
        # make firefox look nice
        firefoxTheme = pkgs.stdenv.mkDerivation rec {
          pname = "firefox-gnome-theme";
          version = "v134";

          src = pkgs.fetchFromGitHub {
            owner = "rafaelmardojai";
            repo = "firefox-gnome-theme";
            tag = version;
            sha256 = "sha256-S79Hqn2EtSxU4kp99t8tRschSifWD4p/51++0xNWUxw=";
          };

          dontConfigure = true;
          dontBuild = true;
          doCheck = false;

          installPhase = ''
            mkdir -p $out/share/firefox-gnome-theme
            cp -r theme/* $out/share/firefox-gnome-theme
          '';
        };
      in
      {
        programs.firefox = {
          enable = true;
          profiles.default = {
            # must-have extensions :)
            extensions = with pkgs.nur.repos.rycee.firefox-addons;
              [
                ublock-origin
                darkreader
                proton-pass
                scroll_anywhere
              ];

            # basic UI, no distractions
            settings = {
              "browser.uidensity" = 0;
              "browser.accounts.enabled" = false;
              "browser.homepage.enabled" = false;
              "browser.newtab.url" = "about:blank";
              "browser.newtabpage.pinned" = [ ];
              "browser.newtabpage.activity-stream.newtabWallpapers.wallpaper" = "dark-blue";
              "browser.newtabpage.activity-stream.feeds.topsites" = false;
              "browser.toolbars.bookmarks.visibility" = "newtab";
              "browser.search.defaultenginename" = "DuckDuckGo";
              "browser.search.selectedEngine" = "DuckDuckGo";
              "browser.search.useDBForOrder" = false;
              "gnomeTheme.activeTabContrast" = true;
              "gnomeTheme.bookmarksToolbarUnderTabs" = true;
              "gnomeTheme.hideSingleTab" = true;
              "gnomeTheme.hideWebrtcIndicator" = true;
              "gnomeTheme.spinner" = true;
              "widget.use-xdg-desktop-portal.file-picker" = 1;
              "extensions.pocket.enabled" = false;
              "browser.toolbarbuttons.introduced.pocket-button" = false;
              "layers.acceleration.force-enabled" = true;
              "svg.context-properties.content.enabled" = true;
              "toolkit.legacyUserProfileCustomizations.stylesheets" = true;
              "widget.gtk.overlay-scrollbars.enabled" = true;
            };

            bookmarks = [
              {
                name = "Preloaded";
                toolbar = true;
                bookmarks =
                  userConfig.shortcuts
                  |> map (s: {
                    inherit (s) name url;
                  });
              }
            ];

            userChrome = ''
              @import "${firefoxTheme}/share/firefox-gnome-theme/gnome-theme.css";
            '';
          };
        };
      }
    )
  ];
}
