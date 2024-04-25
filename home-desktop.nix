{ pkgs, username, ... }: {
  imports = [ ./home-base.nix ];

  home.packages = with pkgs; [
    gnomeExtensions.blur-my-shell
    brave
    obsidian
    protonvpn-gui
    cozy
    drawing
    beeper
    apostrophe
  ];

  gtk = {
    enable = true;
    theme = {
      name = "adw-gtk3-dark";
      package = pkgs.adw-gtk3;
    };
    gtk3.extraConfig.Settings = "gtk-application-prefer-dark-theme=1";
    gtk4.extraConfig.Settings = "gtk-application-prefer-dark-theme=1";
    iconTheme = {
      name = "MoreWaita";
      package = pkgs.morewaita-icon-theme;
    };
    gtk3.bookmarks = [
      "file:///home/${username}/Notes"
    ];
  };

  dconf.settings = {
    ## GNOME Shell Settings
    "org/gnome/desktop/interface" = {
      color-scheme = "prefer-dark";
      enable-hot-corners = true;
    };
    "org/gnome/desktop/wm/preferences".num-workspaces = 3;
    "org/gtk/settings/file-chooser".clock-format = "12h";
    "org/gnome/shell" = {
      favorite-apps = [
        "org.gnome.Nautilus.desktop"
        "org.gnome.Console.desktop"
        "brave-browser.desktop"
        "code.desktop"
      ];
      disable-user-extensions = false;
      enabled-extensions = [ "blur-my-shell@aunetx" ];
    };

    # make alt-tab switch between windows and not applications.
    # this is useful for switching between windows of a web browser.
    "org/gnome/desktop/wm/keybindings" = {
      switch-applications = [ ];
      switch-applications-backward = [ ];
      switch-windows = [ "<Alt>Tab" ];
      switch-windows-backward = [ "<Shift><Alt>Tab" ];
    };
    "org/gnome/shell/window-switcher".current-workspace-only = false;

    ## Extensions and Applications
    "org/gnome/shell/extensions/blur-my-shell/panel".override-background-dynamically = true;
    "org/gnome/Console".custom-font = "Iosevka 12";
  };

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
    };
  };
}
