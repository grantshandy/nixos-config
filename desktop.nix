{ config, pkgs, ... }:
let
  version = "23.11";
  background = pkgs.fetchurl {
    url =
      "https://github.com/grantshandy/dotfiles/blob/main/background.jpg?raw=true";
    hash = "sha256-aT3VWvMshR7ZsSqWACRSlWLEaggu5dfYDaMgyhbuBy4=";
  };
  dark-theme = true;
  morewaita-icon-theme = (with pkgs;
    stdenvNoCC.mkDerivation rec {
      pname = "morewaita-icon-theme";
      version = "43.2";

      src = fetchFromGitHub {
        owner = "somepaulo";
        repo = "MoreWaita";
        rev = "v${version}";
        sha256 = "sha256-efeZEysuWdE1+ws3njFlhWjAjavRlMuIuSL2VT25lUk=";
      };

      nativeBuildInputs = [ gtk3 xdg-utils ];

      installPhase = ''
        install -d $out/share/icons/MoreWaita
        cp -r . $out/share/icons/MoreWaita
        gtk-update-icon-cache -f -t $out/share/icons/MoreWaita && xdg-desktop-menu forceupdate
      '';
    });
in {
  nix.settings.experimental-features = [ "nix-command" "flakes" ];
  nixpkgs.config.allowUnfree = true;
  documentation.nixos.enable = false;

  networking.networkmanager.enable = true;

  # Enable the X11 windowing system.
  services.xserver.enable = true;
  services.xserver.excludePackages = [ pkgs.xterm ];

  # Configure keymap in X11
  services.xserver = {
    layout = "us";
    xkbVariant = "";
  };

  # Enable the GNOME Desktop Environment.
  services.xserver.displayManager.gdm.enable = true;
  services.xserver.desktopManager.gnome.enable = true;
  environment.gnome.excludePackages =
    (with pkgs; [ gnome-photos gnome-tour epiphany gnome-connections ])
    ++ (with pkgs.gnome; [
      gnome-music
      geary
      gnome-contacts
      gnome-calendar
      gnome-maps
    ]);

  fonts.packages = with pkgs; [ noto-fonts noto-fonts-cjk ];

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

  programs.gnupg.agent.enable = true;

  users.users.grant = {
    isNormalUser = true;
    description = "Grant Handy";
    extraGroups = [ "networkmanager" "wheel" ];
  };

  home-manager.useGlobalPkgs = true;
  home-manager.users.grant = { pkgs, ... }: {
    home = {
      username = "grant";
      homeDirectory = "/home/grant";
      stateVersion = version;
      sessionVariables = { EDITOR = "hx"; };
      packages = with pkgs; [
        gnomeExtensions.blur-my-shell
        gnomeExtensions.rounded-window-corners

        hyperfine
        htop
        wget
        translate-shell
        typst

        firefox
        monero-gui
        brave

        # Nix
        nixfmt
        nil

        eclipses.eclipse-java
        morewaita-icon-theme
      ];
    };

    fonts.fontconfig.enable = true;

    gtk = {
      enable = true;
      theme = {
        name = "adw-gtk3${ if dark-theme then "-dark" else "" }";
        package = pkgs.adw-gtk3;
      };
      gtk3.extraConfig.Settings = "gtk-application-prefer-dark-theme=${ if dark-theme then "1" else "0" }";
      gtk4.extraConfig.Settings = "gtk-application-prefer-dark-theme=${ if dark-theme then "1" else "0" }";
    };

    dconf.settings = {
      "org/gnome/desktop/interface" = {
        color-scheme = if dark-theme then "prefer-dark" else "default";
        enable-hot-corners = true;
        icon-theme = "MoreWaita";
      };
      "org/gnome/shell" = {
        favorite-apps = [
          "org.gnome.Nautilus.desktop"
          "brave-browser.desktop"
          "org.gnome.Evince.desktop"
          "org.gnome.Console.desktop"
          "code.desktop"
        ];
        disable-user-extensions = false;
        enabled-extensions = [ "blur-my-shell@aunetx" ];
      };
      "org/gnome/shell/extensions/blur-my-shell/panel" = {
        override-background-dynamically = true;
      };
      "org/gnome/desktop/background" = {
        picture-uri = "${background.outPath}";
        picture-uri-dark = "${background.outPath}";
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
    };

    programs.direnv = {
      enable = true;
      nix-direnv.enable = true;
      config = {
        global.load_dotenv = true;
      };
    };

    programs.vscode = {
      enable = true;
      extensions = with pkgs.vscode-extensions; [
        rust-lang.rust-analyzer
        serayuzgur.crates
        tamasfe.even-better-toml
        jnoortheen.nix-ide
        mkhl.direnv
        usernamehw.errorlens
        bradlc.vscode-tailwindcss
        vscodevim.vim
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
          colorTheme = "Adwaita ${ if dark-theme then "Dark" else "Light" }";
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

    programs.home-manager.enable = true;
  };

  services.flatpak.enable = true;
}
