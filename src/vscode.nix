{ pkgs, ... }:
{
  home-manager.sharedModules = [
    {
      programs.vscode = {
        enable = true;
        package = pkgs.vscode-fhs;
        profiles.default = {
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
              titleBarStyle = "native";
              # commandCenter = true;
              customTitleBarVisibility = "never";
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
            "explorer.confirmDragAndDrop" = false;
          };
        };
      };
    }
  ];
}
