{ pkgs, ... }:
{
  home-manager.sharedModules = [{
    home.packages = with pkgs; [
      obsidian
      protonvpn-gui
      beeper
      dialect
      anki
    ];

    dconf.settings."org/gnome/shell".favorite-apps = [
      "org.gnome.Nautilus.desktop"
      "org.gnome.Console.desktop"
      "brave-browser.desktop"
      "code.desktop"
      "obsidian.desktop"
    ];

    xdg.desktopEntries = {
      Helix = {
        name = "Helix";
        noDisplay = true;
      };
    
      protonMail = {
        name = "Proton Mail";
        terminal = false;
        icon = pkgs.fetchurl {
          url = "https://raw.githubusercontent.com/ProtonMail/WebClients/2dac2f08a7969fe16160b22defb8392c20ef48a0/applications/mail/src/favicon.svg";
          hash = "sha256-ks+X7lCceeS0YQrY0eD9+1N+T26eB8IzLo+Pv0uV1ME=";
        };
        exec = "xdg-open https://mail.proton.me";
      };

      protonCalendar = {
        name = "Proton Calendar";
        terminal = false;
        icon = pkgs.fetchurl {
          url = "https://raw.githubusercontent.com/ProtonMail/WebClients/2dac2f08a7969fe16160b22defb8392c20ef48a0/applications/calendar/src/favicon.svg";
          hash = "sha256-oiiaF3IySz/HXT5p7hsVGdT35364hbk82K1B4l6Ktck=";
        };
        exec = "xdg-open https://calendar.proton.me";
      };
    };

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
