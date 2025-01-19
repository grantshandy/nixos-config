{ pkgs, lib, userConfig, nur, ... }:
{
  home-manager.sharedModules = [
    {
      home.packages = with pkgs; [
        obsidian
        protonvpn-gui
        beeper
        anki
        prismlauncher
      ];

      programs.firefox = {
        enable = true;
        profiles.default = {
          extensions =
            with nur.legacyPackages."x86_64-linux".repos.rycee.firefox-addons; [
              ublock-origin
              darkreader
              # scroll_anywhere
            ];
          settings = {
            "browser.uidensity" = 0;
            "gnomeTheme.activeTabContrast" = true;
            "gnomeTheme.bookmarksToolbarUnderTabs" = true;
            "gnomeTheme.hideSingleTab" = true;
            "gnomeTheme.hideWebrtcIndicator" = true;
            "gnomeTheme.spinner" = true;
            "layers.acceleration.force-enabled" = true;
            "svg.context-properties.content.enabled" = true;
            "toolkit.legacyUserProfileCustomizations.stylesheets" = true;
            "widget.gtk.overlay-scrollbars.enabled" = true;
          };
          userChrome = ''
            @import "${(pkgs.callPackage ../pkgs/firefox-gnome-theme.nix pkgs)}/share/firefox-gnome-theme/gnome-theme.css";
          '';
        };
      };

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

    (
      let
        iconDir = "${pkgs.morewaita-icon-theme}/share/icons/MoreWaita/scalable/apps";
      in
      {
        xdg.desktopEntries = builtins.listToAttrs (map
          (shortcut: {
            name = lib.toLower (builtins.replaceStrings [ " " ] [ "" ] shortcut.name);
            value =
              {
                name = shortcut.name;
                icon =
                  if builtins.typeOf shortcut.icon == "set" then
                    pkgs.fetchurl { inherit (shortcut.icon) url hash; }
                  else
                    "${iconDir}/${shortcut.icon}";
                terminal = false;
                exec = "xdg-open ${shortcut.url}";
              };
          })
          userConfig.shortcuts);
      }
    )
  ];
}
