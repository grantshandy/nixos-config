{lib, ...}: {
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

      searchEngines = lib.mkOption {
        type = lib.types.attrsOf lib.types.str;
        default = {};
        description = "Extra local-search-shortcuts engines: name -> URL template with {s}.";
      };
    };
  };

  options.desktop = {
    favoriteApps = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [];
      description = ".desktop IDs to pin to the dash, contributed by other modules.";
    };
  };

  options.network.hosts = lib.mkOption {
    type = lib.types.attrsOf (lib.types.submodule {
      options = {
        system = lib.mkOption {
          type = lib.types.str;
          default = "x86_64-linux";
        };
        ssh = {
          enable = lib.mkOption {
            type = lib.types.bool;
            default = false;
          };
          port = lib.mkOption {
            type = lib.types.port;
            default = 22;
          };
        };
        tailscale.enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
        };
      };
    });
    default = {};
  };

  options.identity.homelab.dns = lib.mkOption {type = lib.types.str;};
}
