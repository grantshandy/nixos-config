{
  fleet.aspects.firefox.tags = ["desktop"];

  flake.modules.homeManager.firefox = {
    inputs,
    config,
    lib,
    pkgs,
    ...
  }: let
    fx = config.identity.firefox;
  in {
    imports = [
      ( # home-manager module that automatically enables local-search-shortcuts.
        {
          config,
          lib,
          pkgs,
          ...
        }: let
          name = "local-search-shortcuts";
          package = pkgs.rustPlatform.buildRustPackage rec {
            pname = name;
            version = "1.2.3";

            src = pkgs.fetchFromGitHub {
              owner = "grantshandy";
              repo = name;
              rev = version;
              hash = "sha256-ylIeBGKMtR9Lj2gk1Pkzs/zi4NLjI5sJyYgmTVXjkrk=";
            };

            cargoHash = "sha256-Kxrucvdy/ECkQrXmXiDct6/bO1yF76JZc/OSmvginVU=";
            meta.mainProgram = name;
          };

          cfg = config.services.${name};
        in {
          options.services.${name} = {
            enable = lib.mkEnableOption name;

            firefoxSearch = lib.mkEnableOption "Set the ${name} provider as the default search engine in Firefox.";

            port = lib.mkOption {
              type = lib.types.port;
              default = 9321;
            };

            broadcast = lib.mkOption {
              type = lib.types.bool;
              default = false;
            };

            engines = lib.mkOption {
              type = lib.types.attrs;
              default = {};
            };

            default = lib.mkOption {
              type = lib.types.str;
              default = "ddg";
            };

            displayName = lib.mkOption {
              type = lib.types.str;
              default = "lss";
            };
          };

          config = let
            configFile = (pkgs.formats.toml {}).generate "${name}-config.toml" {
              inherit (cfg) port engines default broadcast;
            };
          in
            lib.mkIf cfg.enable {
              xdg.configFile."${name}/config.toml".source = configFile;

              systemd.user.services.${name} = {
                Unit = {
                  Description = "Local Search Shortcuts";
                  After = ["network.target"];
                  X-Restart-Triggers = [
                    configFile
                  ];
                };
                Service = {
                  ExecStart = lib.getExe package;
                  Restart = "always";
                };
                Install.WantedBy = ["default.target"];
              };

              programs.firefox.profiles.default.search =
                lib.mkIf cfg.firefoxSearch
                {
                  force = true;
                  default = cfg.displayName;
                  privateDefault = cfg.displayName;
                  engines.${cfg.displayName}.urls = [
                    {
                      template = "http://localhost:${toString cfg.port}/";
                      params = [
                        {
                          name = "q";
                          value = "{searchTerms}";
                        }
                      ];
                    }
                  ];
                };
            };
        }
      )
    ];

    desktop.favoriteApps = lib.mkOrder 200 ["firefox.desktop"];

    services.local-search-shortcuts = {
      enable = true;
      firefoxSearch = true;
      engines = fx.searchEngines;
      default = fx.defaultEngine;
    };

    programs.firefox = {
      enable = true;
      package = pkgs.firefox.override {
        cfg.enableWayland = true;
      };

      configPath = ".config/mozilla/firefox";

      # This method for installing plugins here largely from:
      # https://discourse.nixos.org/t/declare-firefox-extensions-and-settings/36265/7
      policies = {
        # Settings:
        # https://mozilla.github.io/policy-templates/
        DisableFeedbackCommands = true;
        DisableFirefoxAccounts = true;
        DisablePocket = true;
        DisableTelemetry = true;
        OfferToSaveLogins = false;
        OfferToSaveLoginsDefault = false;

        EncryptedMediaExtensions = {
          Enabled = true;
          Locked = true;
        };

        UserMessaging = {
          SkipOnboarding = true;
          Locked = true;
        };

        ExtensionSettings =
          fx.extensions
          |> map (name: inputs.firefox-addons.packages.${pkgs.stdenv.hostPlatform.system}.${name})
          |> map (ext: {
            name = ext.addonId;
            value = {
              installation_mode = "force_installed";
              install_url = "file://${ext}/share/mozilla/extensions/{ec8030f7-c20a-464f-9b0e-13a3a9e97384}/${ext.addonId}.xpi";
            };
          })
          |> builtins.listToAttrs;
      };

      profiles.default = {
        isDefault = true;

        settings = {
          # enable stylesheets
          "toolkit.legacyUserProfileCustomizations.stylesheets" = true;

          # gnome theme settings:
          "gnomeTheme.activeTabContrast" = true;
          "gnomeTheme.bookmarksToolbarUnderTabs" = true;
          "gnomeTheme.hideSingleTab" = true;
          "gnomeTheme.hideWebrtcIndicator" = true;
          "gnomeTheme.spinner" = true;

          # sync look with GTK
          "widget.use-xdg-desktop-portal.file-picker" = 1;
          "widget.gtk.overlay-scrollbars.enabled" = true;
          "widget.gtk.rounded-bottom-corners.enabled" = true;

          # mouse behavior
          "general.autoScroll" = true;
          "middlemouse.paste" = false;

          "browser.uiCustomization.state" = builtins.readFile ./ui.json;
          "browser.uidensity" = 0;
          "browser.accounts.enabled" = false;
          "browser.homepage.enabled" = false;

          "browser.newtab.url" = "about:blank";
          "browser.newtabpage.pinned" = "[]";
          "browser.newtabpage.activity-stream.newtabWallpapers.wallpaper" = "";
          "browser.newtabpage.activity-stream.newtabWallpapers.wallpaper-dark" = "";
          "browser.newtabpage.activity-stream.newtabWallpapers.wallpaper-light" = "";
          "browser.newtabpage.activity-stream.showWeather" = false;
          "browser.newtabpage.activity-stream.widgets.weather.enabled" = false;
          "browser.newtabpage.activity-stream.feeds.section.topstories" = false;
          "browser.newtabpage.activity-stream.feeds.topsites" = false;
          "browser.toolbars.bookmarks.visibility" = "newtab";
          "browser.search.useDBForOrder" = false;
          "browser.aboutConfig.showWarning" = false;
          "browser.aboutwelcome.didSeeFinalScreen" = true;

          "browser.urlbar.suggest.quickactions" = false;
          "browser.urlbar.suggest.quicksuggest.nonsponsored" = false;
          "browser.urlbar.suggest.quicksuggest.sponsored" = false;
          "browser.urlbar.suggest.topsites" = false;

          "media.eme.enabled" = true;
          "extensions.pocket.enabled" = false;
          "browser.toolbarbuttons.introduced.pocket-button" = false;
          "layers.acceleration.force-enabled" = true;
          "svg.context-properties.content.enabled" = true;
        };

        bookmarks = {
          force = true;
          settings =
            [
              {
                name = "NixOS Managed";
                toolbar = true;
                bookmarks = lib.mapAttrsToList (name: url: {inherit name url;}) fx.bookmarks;
              }
            ]
            ++ lib.optional (fx.homelabBookmarks != {}) {
              name = "Homelab";
              toolbar = true;
              bookmarks = lib.mapAttrsToList (name: url: {inherit name url;}) fx.homelabBookmarks;
            };
        };

        userChrome = let
          theme = pkgs.fetchFromGitHub {
            owner = "rafaelmardojai";
            repo = "firefox-gnome-theme";
            tag = "v157.1";
            sha256 = "sha256-mg4JrSm2ym4dXyLeBS7/4/G7aLg0bxssTjEaJXymHrE=";
          };
        in ''
          @import "${theme}/theme/gnome-theme.css";

          .urlbarView:not(:has(> .urlbarView-body-outer)) > .urlbarView-background {
            background: var(--gnome-menu-background) !important;
            border-radius: var(--gnome-popover-radius) !important;
            clip-path: none !important;
            inset: 0 !important;
          }

          .urlbarView:not(:has(> .urlbarView-body-outer)) > .urlbarView-results {
            padding: var(--gnome-menu-padding) calc(var(--gnome-menu-padding) + 2px) !important;
          }
        '';
      };
    };
  };
}
