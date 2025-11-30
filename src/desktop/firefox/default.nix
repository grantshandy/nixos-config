{
  inputs,
  pkgs-unstable,
  pkgs,
  lib,
  userConfig,
  ...
}: {
  home-manager.sharedModules = [
    {
      imports = [
        ./local-search-shortcuts.nix
      ];

      dconf.settings."org/gnome/shell".favorite-apps = ["firefox.desktop"];

      services.local-search-shortcuts = {
        enable = true;
        firefoxSearch = true;
        settings = {
          default = userConfig.firefox.default-engine or "DuckDuckGo";
          engines = userConfig.firefox.extra-engines or {};
        };
      };

      programs.firefox = {
        enable = true;
        package = pkgs-unstable.firefox;

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
            userConfig.firefox.extensions
            |> map (name: inputs.firefox-addons.packages.${pkgs.system}.${name})
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
          settings = {
            # gnome theme settings:
            "gnomeTheme.activeTabContrast" = true;
            "gnomeTheme.bookmarksToolbarUnderTabs" = true;
            "gnomeTheme.hideSingleTab" = true;
            "gnomeTheme.hideWebrtcIndicator" = true;
            "gnomeTheme.spinner" = true;

            # mouse behavior
            "general.autoScroll" = true;
            "middlemouse.paste" = false;

            "browser.uiCustomization.state" = builtins.readFile ./ui.json |> builtins.fromJSON;
            "browser.uidensity" = 0;
            "browser.accounts.enabled" = false;
            "browser.homepage.enabled" = false;

            "browser.newtab.url" = "about:blank";
            "browser.newtabpage.pinned" = [];
            "browser.newtabpage.activity-stream.newtabWallpapers.wallpaper" = "";
            "browser.newtabpage.activity-stream.newtabWallpapers.wallpaper-dark" = "";
            "browser.newtabpage.activity-stream.newtabWallpapers.wallpaper-light" = "";
            "browser.newtabpage.activity-stream.showWeather" = false;
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
            "widget.use-xdg-desktop-portal.file-picker" = 1;
            "extensions.pocket.enabled" = false;
            "browser.toolbarbuttons.introduced.pocket-button" = false;
            "layers.acceleration.force-enabled" = true;
            "svg.context-properties.content.enabled" = true;
            "toolkit.legacyUserProfileCustomizations.stylesheets" = true;
            "widget.gtk.overlay-scrollbars.enabled" = true;
          };

          bookmarks = {
            force = true;
            settings = [
              {
                name = "User Added";
                toolbar = true;
                bookmarks = userConfig.firefox.bookmarks;
              }
            ];
          };

          userChrome = let
            theme = pkgs.fetchFromGitHub {
              owner = "rafaelmardojai";
              repo = "firefox-gnome-theme";
              rev = "v143";
              sha256 = "sha256-0E3TqvXAy81qeM/jZXWWOTZ14Hs1RT7o78UyZM+Jbr4=";
            };
          in ''
            @import "${theme}/theme/gnome-theme.css";
          '';
        };
      };
    }
  ];
}
