{ pkgs, username, ... }: {
  imports = [ ./home-base.nix ];

  gtk = {
    enable = true;
    theme = {
      name = "adw-gtk3-dark";
      package = pkgs.adw-gtk3;
    };
    gtk3.extraConfig.Settings = "gtk-application-prefer-dark-theme=1";
    gtk4.extraConfig.Settings = "gtk-application-prefer-dark-theme=1";
  };

  home.packages = with pkgs; with gnomeExtensions; [ morewaita-icon-theme blur-my-shell ];
  dconf.settings = {
    "org/gnome/desktop/interface" = {
      color-scheme = "prefer-dark";
      enable-hot-corners = true;
      icon-theme = "MoreWaita";
    };
    "org/gnome/desktop/wm/preferences" = {
      num-workspaces = 2;
    };
    "org/gtk/settings/file-chooser" = {
      clock-format = "12h";
    };
    "org/gnome/shell" = {
      favorite-apps = [
        "org.gnome.Nautilus.desktop"
        "org.gnome.Console.desktop"
        "code.desktop"
      ];
      disable-user-extensions = false;
      enabled-extensions = [ "blur-my-shell@aunetx" ];
    };
    "org/gnome/shell/extensions/blur-my-shell/panel" = {
      override-background-dynamically = true;
    };
  };

  programs.vscode = {
    enable = true;
    package = pkgs.vscode;
    extensions = with pkgs.vscode-extensions; [
      rust-lang.rust-analyzer
      serayuzgur.crates
      tamasfe.even-better-toml
      jnoortheen.nix-ide
      mkhl.direnv
      usernamehw.errorlens
      bradlc.vscode-tailwindcss
      piousdeer.adwaita-theme
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
      };
      editor = {
        quickSuggesions = {
          other = "on";
          comments = "on";
          strings = "on";
        };
        renderLineHighlight = "none";
      };
    };
  };

}
