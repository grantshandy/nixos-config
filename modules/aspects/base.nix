# What it means to be a machine in this fleet, in both module classes.
#
# This includes the inseparable fleet foundation: shared options, identity,
# compatibility versions, and NixOS secret decryption. Independent policies such
# as networking, bootloader selection, build-cluster participation, and
# monitoring remain separate aspects.
{
  config,
  inputs,
  ...
}: let
  stateVersion = config.fleet.stateVersion;
  identityModule = ../../identity.nix;

  # Installed in both evaluations so NixOS and Home Manager modules can consume
  # the same identity and cross-feature option namespaces.
  sharedOptions = {lib, ...}: {
    options.configuration.stateVersion = lib.mkOption {
      type = lib.types.str;
      description = "Compatibility version shared by NixOS and Home Manager.";
    };

    options.identity = {
      user = {
        name = lib.mkOption {type = lib.types.str;};
        description = lib.mkOption {
          type = lib.types.str;
          default = "";
        };
      };

      homelab.dns = lib.mkOption {type = lib.types.str;};

      ssh = {
        userKeys = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [];
          description = "Public SSH keys authorized for the primary user.";
        };
        hostKeys = lib.mkOption {
          type = lib.types.attrsOf lib.types.str;
          default = {};
          description = "Public SSH host keys, keyed by host name.";
        };
      };

      git = {
        name = lib.mkOption {type = lib.types.str;};
        email = lib.mkOption {type = lib.types.str;};
      };

      firefox = {
        defaultEngine = lib.mkOption {
          type = lib.types.str;
          default = "ddg";
        };

        extensions = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [];
          description = "Addon names as published by the firefox-addons NUR expression.";
        };

        bookmarks = lib.mkOption {
          type = lib.types.attrsOf lib.types.str;
          default = {};
          description = "Firefox bookmarks as name-to-URL pairs.";
        };

        homelabBookmarks = lib.mkOption {
          type = lib.types.attrsOf lib.types.str;
          default = {};
          description = "Registry-derived homelab bookmarks as name-to-URL pairs.";
        };

        searchEngines = lib.mkOption {
          type = lib.types.attrsOf lib.types.str;
          default = {};
          description = "Extra local-search-shortcuts engines: name -> URL template with {s}.";
        };
      };
    };

    options.desktop.favoriteApps = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [];
      description = ".desktop IDs to pin to the dash, contributed by other modules.";
    };
  };
in {
  fleet.aspects.base.default = true;

  flake.modules.nixos.base = {config, ...}: {
    imports = [
      inputs.agenix.nixosModules.default
      identityModule
      sharedOptions
    ];

    configuration.stateVersion = stateVersion;

    i18n = let
      lc = "en_US.UTF-8";
    in {
      defaultLocale = lc;
      extraLocaleSettings.LC_ALL = lc;
    };

    nixpkgs.config.allowUnfree = true;
    nix.settings = {
      trusted-users = [config.identity.user.name];
      experimental-features = [
        "nix-command"
        "flakes"
        "pipe-operators"
      ];
      auto-optimise-store = true;
    };
    nix.registry = {
      nixpkgs.flake = inputs.nixpkgs;
      nixpkgs-unstable.flake = inputs.nixpkgs-unstable;
    };
    documentation.nixos.enable = false;

    users.users."${config.identity.user.name}" = {
      isNormalUser = true;
      description = config.identity.user.description;
      extraGroups = [
        "networkmanager"
        "wheel"
      ];
      openssh.authorizedKeys.keys = config.identity.ssh.userKeys;
    };

    security.sudo.extraRules = [
      {
        users = [config.identity.user.name];
        commands = [
          {
            command = "ALL";
            options = ["NOPASSWD"];
          }
        ];
      }
    ];

    system.stateVersion = config.configuration.stateVersion;
  };

  flake.modules.homeManager.base = {
    pkgs,
    config,
    ...
  }: {
    imports = [
      identityModule
      sharedOptions
    ];

    configuration.stateVersion = stateVersion;

    home.packages = with pkgs; [
      git
      btop
      vim
      nix-tree
      ascii
      alejandra
      file
      tree
      ripgrep
      tldr
      fastfetch
    ];

    programs.tmux = {
      enable = true;

      shortcut = "a";
      escapeTime = 0;

      plugins = [
        pkgs.tmuxPlugins.better-mouse-mode
      ];

      extraConfig = ''
        # https://old.reddit.com/r/tmux/comments/mesrci/tmux_2_doesnt_seem_to_use_256_colors/
        set -g default-terminal "xterm-256color"
        set -ga terminal-overrides ",*256col*:Tc"
        set -ga terminal-overrides '*:Ss=\E[%p1%d q:Se=\E[ q'
        set-environment -g COLORTERM "truecolor"

        # Mouse works as expected
        set-option -g mouse on

        # easy-to-remember split pane commands
        bind | split-window -h -c "#{pane_current_path}"
        bind - split-window -v -c "#{pane_current_path}"
        bind c new-window -c "#{pane_current_path}"

        # vim-like pane resizing
        bind -r C-k resize-pane -U
        bind -r C-j resize-pane -D
        bind -r C-h resize-pane -L
        bind -r C-l resize-pane -R

        # vim-like pane switching
        bind -r k select-pane -U
        bind -r j select-pane -D
        bind -r h select-pane -L
        bind -r l select-pane -R

        # and now unbind keys
        unbind Up
        unbind Down
        unbind Left
        unbind Right

        unbind C-Up
        unbind C-Down
        unbind C-Left
        unbind C-Right
      '';
    };

    programs.bash = {
      enable = true;
      enableCompletion = true;
    };

    programs.direnv = {
      enable = true;
      nix-direnv.enable = true;
      config.global.load_dotenv = true;
    };

    programs.git = {
      enable = true;
      settings.user = config.identity.git;
    };

    programs.gh = {
      enable = true;
      settings.git_protocol = "https";
    };
  };
}
