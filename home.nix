{ config, pkgs, ... }:

{
  home = {
    username = "grant";
    homeDirectory = "/home/grant";
    stateVersion = "23.05";
    sessionVariables = { EDITOR = "hx"; };
    packages = with pkgs; [
      # nice thingys
      gnomeExtensions.blur-my-shell
      papirus-icon-theme
      iosevka

      # CLI Tools
      htop
      wget
      translate-shell
      typst

      # GUI Applications
      blackbox-terminal
      brave
      inkscape
      libreoffice-fresh

      # Rust Development
      nixfmt
      rustup
      crate2nix

      # Java Development
      jdk17
      eclipses.eclipse-java


      # bruh.
      gnome.gnome-boxes
    ];
  };

  fonts.fontconfig.enable = true;

  gtk = {
    enable = true;
    theme = {
      name = "adw-gtk3-dark";
      package = pkgs.adw-gtk3;
    };
    gtk3.extraConfig.Settings = "gtk-application-prefer-dark-theme=1";
    gtk4.extraConfig.Settings = "gtk-application-prefer-dark-theme=1";
  };

  dconf.settings = {
    "org/gnome/desktop/interface" = {
      color-scheme = "prefer-dark";
      enable-hot-corners = true;
      icon-theme = "Papirus";
    };
    "org/gnome/shell" = {
      favorite-apps = [
        "org.gnome.Nautilus.desktop"
        "brave-browser.desktop"
        "org.gnome.Evince.desktop"
        "com.raggesilver.BlackBox.desktop"
      ];
      disable-user-extensions = false;
      enabled-extensions = [ "blur-my-shell@aunetx" ];
    };
    "org/gnome/desktop/background" = {
      picture-uri = "/home/grant/.config/home-manager/background.jpg";
      picture-uri-dark = "/home/grant/.config/home-manager/background.jpg";
    };
    "com/raggesilver/BlackBox" = {
      cursor-blink-mode = 2; # off
      font = "Iosevka Medium Extended 11";
      theme-dark = "base16: Twilight (dark)";
    };
  };

  programs.git = {
    enable = true;
    userName = "grantshandy";
    userEmail = "granthandy@proton.me";
  };

  programs.gh = {
    enable = true;
    settings = {
      git_protocol = "https";
      editor = "hx";
    };
  };

  programs.helix = {
    enable = true;
    settings = {
      theme = "adwaita-dark";
      editor = {
        bufferline = "multiple";
        auto-format = false;
        lsp.display-messages = true;
        soft-wrap.enable = true;
        indent-guides.render = true;
        statusline = {
          left = [ "mode" "spinner" ];
          center = [ "file-name" ];
          right = [
            "diagnostics"
            "selections"
            "position"
            "file-encoding"
            "file-line-ending"
            "file-type"
          ];
          separator = "|";
          mode = {
            normal = "NORMAL";
            insert = "INSERT";
            select = "SELECT";
          };
        };
      };
    };
    languages.language = [{
      name = "rust";
      auto-format = false;
    }];
  };

  programs.tmux = {
    enable = true;
    escapeTime = 0;
    historyLimit = 100000;
    mouse = true;
    extraConfig = ''
      unbind r
      bind r source-file ~/.tmux.conf \; display "Reloaded ~/.tmux.conf"
    '';
  };

  programs.bash = {
    enable = true;
    enableCompletion = true;
    initExtra =
      ''[ -z "$TMUX"  ] && { tmux attach || exec tmux new-session && exit;}'';
  };

  programs.home-manager.enable = true;
}
