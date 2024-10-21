{ pkgs, lib, userConfig, ... }:
{
  home-manager.sharedModules = [
    {
      home.packages = with pkgs; [
        obsidian
        protonvpn-gui
        beeper
        anki
        mars-mips
        inkscape
        shotwell
      ];

      dconf.settings."org/gnome/shell".favorite-apps = [
        "org.gnome.Nautilus.desktop"
        "org.gnome.Console.desktop"
        "brave-browser.desktop"
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

      programs.brave = {
        enable = true;
        extensions = lib.lists.forEach userConfig.browser-extensions (id: { inherit id; });
      };
    }

    (
      let
        iconDir = "${pkgs.morewaita-icon-theme}/share/icons/MoreWaita/apps/scalable";
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
