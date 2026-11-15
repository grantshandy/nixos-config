{lib, ...}: let
  commonServiceOptions = {name, ...}: {
    options = {
      title = lib.mkOption {
        type = lib.types.str;
        default = name;
        description = "Human-readable service name used for bookmarks.";
      };
      description = lib.mkOption {
        type = lib.types.str;
        default = "";
        description = "Description displayed in the service directory.";
      };
      bookmark = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Whether to include this service in Firefox bookmarks.";
      };
      path = lib.mkOption {
        type = lib.types.str;
        default = "/";
        description = "Absolute URL path for the service.";
      };
    };
  };
in {
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
        cache = {
          enable = lib.mkOption {
            type = lib.types.bool;
            default = false;
            description = "Whether this host serves its Nix store to cache peers.";
          };
          priority = lib.mkOption {
            type = lib.types.ints.positive;
            default = 40;
            description = "Binary cache priority; lower values are preferred.";
          };
          port = lib.mkOption {
            type = lib.types.port;
            default = 5000;
            description = "Tailscale-only nix-serve port.";
          };
        };

        publicWebServices = lib.mkOption {
          type = lib.types.attrsOf (lib.types.submodule {
            imports = [commonServiceOptions];
            options = {
              showInDirectory = lib.mkOption {
                type = lib.types.bool;
                default = true;
                description = "Whether to include this service in the host's service directory.";
              };
              redirectPaths = lib.mkOption {
                type = lib.types.listOf lib.types.str;
                default = [];
                description = "Apex-domain paths redirected to this service's public URL.";
              };
              subdomain = lib.mkOption {
                type = lib.types.nullOr lib.types.str;
                default = null;
                description = "Subdomain relative to identity.homelab.dns, or null for the apex domain.";
              };
            };
          });
          default = {};
          description = "Public web services provided by this host.";
        };
        privateWebServices = lib.mkOption {
          type = lib.types.attrsOf (lib.types.submodule {
            imports = [commonServiceOptions];
            options = {
              scheme = lib.mkOption {
                type = lib.types.str;
                default = "http";
                description = "URL scheme for the private service.";
              };
              port = lib.mkOption {
                type = lib.types.port;
                description = "Required port for the private service on the host's Tailscale address.";
              };
            };
          });
          default = {};
          description = "Private web services at <scheme>://<host>.ts.<identity.homelab.dns>:<port><path>.";
        };
      };
    });
    default = {};
  };

  options.identity.homelab.dns = lib.mkOption {type = lib.types.str;};
}
