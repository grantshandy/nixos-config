{ pkgs, ... }:
{
  environment.gnome.excludePackages = [ pkgs.epiphany ];
  fonts.packages = with pkgs; [ iosevka ];

  home-manager.sharedModules = [{
    home.packages = with pkgs; [
      obsidian
      protonvpn-gui
      beeper
      dialect
    ];

    dconf.settings = {
      "org/gnome/shell".favorite-apps = [
        "org.gnome.Nautilus.desktop"
        "org.gnome.Console.desktop"
        "brave-browser.desktop"
        "code.desktop"
      ];
    };

    dconf.settings."org/gnome/Console".custom-font = "Iosevka 12";

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
      dictionaries = [ pkgs.hunspellDictsChromium.en-us ];
      extensions = [
        { id = "eimadpbcbfnmbkopoojfekhnkhdbieeh"; } # Dark Reader
        { id = "jehmdpemhgfgjblpkilmeoafmkhbckhi"; } # Scroll Anywhere
      ];
    };
  }];
}
