{ config, pkgs, ... }:
let
  version = "23.05";
  home-manager = builtins.fetchTarball
    "https://github.com/nix-community/home-manager/archive/release-${version}.tar.gz";
  background = ./background.jpg;
in {
  imports = [ (import "${home-manager}/nixos") ];

  # Enable the X11 windowing system.
  services.xserver.enable = true;
  services.xserver.excludePackages = [ pkgs.xterm ];

  # Enable the GNOME Desktop Environment.
  services.xserver.displayManager.gdm.enable = true;
  services.xserver.desktopManager.gnome.enable = true;
  environment.gnome.excludePackages =
    (with pkgs; [ gnome-photos gnome-tour epiphany ])
    ++ (with pkgs.gnome; [ cheese gnome-music geary gnome-contacts ]);

  # Configure keymap in X11
  services.xserver = {
    layout = "us";
    xkbVariant = "";
  };

  # Enable CUPS to print documents.
  services.printing.enable = true;

  # Enable sound with pipewire.
  sound.enable = true;
  hardware.pulseaudio.enable = false;
  security.rtkit.enable = true;
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
  };

  users.users.grant = {
    isNormalUser = true;
    description = "Grant Handy";
    extraGroups = [ "networkmanager" "wheel" ];
    packages = with pkgs; [ ];
  };

  home-manager.users.grant = { pkgs, ... }: {
    home = {
      username = "grant";
      homeDirectory = "/home/grant";
      stateVersion = version;
      sessionVariables = { EDITOR = "hx"; };
      packages = (with pkgs; [
        gnomeExtensions.blur-my-shell
        papirus-icon-theme

        htop
        wget
        translate-shell
        typst

        brave
        logseq

        # Rust
        nixfmt
        rustup
        crate2nix

      ]) ++ (with pkgs.eclipses; [ eclipse-java ]);
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
          "org.gnome.Console.desktop"
        ];
        disable-user-extensions = false;
        enabled-extensions = [ "blur-my-shell@aunetx" ];
      };
      "org/gnome/shell/extensions/blur-my-shell/panel" = {
        override-background-dynamically = true;
      };
      "org/gnome/desktop/background" = {
        picture-uri = "${background}";
        picture-uri-dark = "${background}";
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
  };
}
