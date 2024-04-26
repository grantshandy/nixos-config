{ pkgs, username, ... }: {
  environment.gnome.excludePackages = [ pkgs.epiphany ];
  fonts.packages = [ pkgs.iosevka ];

  home-manager.users."${username}" = { pkgs, username, ... }: {
    home.packages = with pkgs; [
      brave
      obsidian
      protonvpn-gui
      cozy
      drawing
      beeper
      apostrophe
      shotwell
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
        serayuzgur.crates
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
          titleBarStyle = "custom";
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
        "nix.serverPath" =  "${pkgs.nixd}/bin/nixd";
      };
    };
  };
}
