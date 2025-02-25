{
  inputs,
  pkgs,
  lib,
  userConfig,
  ...
}:
{
  home-manager.sharedModules = [
    {
      programs.firefox.enable = true;

      # This method for installing plugins here largely from:
      # https://discourse.nixos.org/t/declare-firefox-extensions-and-settings/36265/7
      programs.firefox.policies = {
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

        ExtensionSettings = lib.mkMerge [
          {
            "*" = {
              "blocked_install_message" = "Extensions are handled by Nix!";
              "installation_mode" = "blocked";
            };
          }

          (
            userConfig.firefox.extensions
            |> map (name: inputs.firefox-addons.packages.${pkgs.system}.${name})
            |> map (ext: {
              name = ext.addonId;
              value = {
                installation_mode = "force_installed";
                install_url = "file://${ext}/share/mozilla/extensions/{ec8030f7-c20a-464f-9b0e-13a3a9e97384}/${ext.addonId}.xpi";
              };
            })
            |> builtins.listToAttrs
          )
        ];
      };

      programs.firefox.profiles.default = {
        search = {
          force = true;
          default = "DuckDuckGo";
          privateDefault = "DuckDuckGo";
        };

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
          "browser.newtabpage.pinned" = [ ];
          "browser.newtabpage.activity-stream.newtabWallpapers.wallpaper" = "";
          "browser.newtabpage.activity-stream.newtabWallpapers.wallpaper-dark" = "";
          "browser.newtabpage.activity-stream.newtabWallpapers.wallpaper-light" = "";

          "browser.newtabpage.activity-stream.feeds.topsites" = false;
          "browser.toolbars.bookmarks.visibility" = "newtab";
          "browser.search.useDBForOrder" = false;
          "browser.aboutConfig.showWarning" = false;
          "browser.aboutwelcome.didSeeFinalScreen" = true;

          "media.eme.enabled" = true;
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
            toolbar = true;
            bookmarks = userConfig.firefox.bookmarks;
          }
        ];

        userChrome =
          let
            theme = pkgs.fetchFromGitHub {
              owner = "rafaelmardojai";
              repo = "firefox-gnome-theme";
              tag = "v134";
              sha256 = "sha256-S79Hqn2EtSxU4kp99t8tRschSifWD4p/51++0xNWUxw=";
            };
          in
          ''
            @import "${theme}/theme/gnome-theme.css";
          '';
      };
    }
  ];
}
