{ pkgs, homeDirectory, username, ... }:
let cameraDir = "${homeDirectory}/Pictures/Camera"; in
let notesDir = "${homeDirectory}/Notes"; in
{
  environment.gnome.excludePackages = [ pkgs.epiphany ];
  fonts.packages = [ pkgs.iosevka ];

  home-manager.sharedModules = [{
    home.packages = with pkgs; [
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
        { id = "bfhkfdnddlhfippjbflipboognpdpoeh"; } # Read on reMarkable
      ];
    };

    services.syncthing = {
      enable = true;
      openDefaultPorts = true;

      dataDir = "${homeDirectory}";
      user = "${username}";

      overrideDevices = true;
      settings.devices."phone" = {
        name = "Phone";
        id = "5IBK4XI-3SBE6A7-JCU7L3E-UB3W45N-SMPSC5C-HDHSVBG-UM6XUI6-HQHUSAA";
      };

      overrideFolders = true;
      settings.folders = {
        notes = {
          enable = true;
          id = "gsnotes";
          label = "Notes";
          path = notesDir;
          devices = [ "phone" ];
        };
        photos = {
          enable = true;
          id = "gsphotos";
          label = "Camera";
          path = cameraDir;
          devices = [ "phone" ];
        };
      };
    };

    home-manager.sharedModules = [{
      gtk.gtk3.bookmarks = [ "file://${notesDir}" "file://${cameraDir}" ];
    }];
  }];
}
