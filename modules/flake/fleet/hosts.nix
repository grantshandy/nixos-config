# The fleet registry: facts about every machine, typed once at the flake level
# instead of re-typed inside each system evaluation.
{lib, ...}: let
  inherit (lib) mkOption types;
in {
  options.fleet = {
    stateVersion = mkOption {
      type = types.str;
      description = "Compatibility version shared by NixOS and Home Manager.";
    };

    hosts = mkOption {
      default = {};
      description = "Every machine in the fleet, keyed by host name.";
      type = types.attrsOf (types.submodule {
        options = {
          system = mkOption {
            type = types.str;
            default = "x86_64-linux";
          };

          tags = mkOption {
            type = types.listOf types.str;
            default = [];
            description = ''
              Roles this host plays. Aspects enroll themselves against tags, so
              adding a tag here is how a host picks up a whole class of features.
            '';
          };

          aspects = mkOption {
            type = types.listOf types.str;
            default = [];
            description = ''
              Aspects this host opts into by name. Order is preserved and comes
              first, so list-valued options merge predictably.
            '';
          };

          proxyPort = mkOption {
            type = types.nullOr types.port;
            default = null;
            description = ''
              Port of this host's own reverse proxy. The edge reaches services
              hosted here through it unless they ask for a direct upstream.
            '';
          };

          extraStorageRoot = mkOption {
            type = types.path;
            description = ''
              Where services on this host put data that should not live in
              /var/lib: bulk libraries, caches, CI build trees. Services that
              want a slice of it derive their own subdirectory from this, so a
              service follows its tag onto any machine without naming a path.

              Every host declares one even if nothing currently uses it. It need
              not be a separate drive -- a plain directory on the root
              filesystem is a valid answer for a host with no spare spindle, and
              consumers must not assume there is a mount unit behind it.
            '';
          };

          homeManager.enable = mkOption {
            type = types.bool;
            default = true;
            description = "Whether to manage the primary user's profile with Home Manager.";
          };

          remoteDevelopment.enable = mkOption {
            type = types.bool;
            default = true;
            description = "Whether to install Waypipe and the Zed remote server for development over SSH.";
          };

          ssh = {
            enable = mkOption {
              type = types.bool;
              default = false;
            };
            port = mkOption {
              type = types.port;
              default = 22;
            };
          };

          tailscale = {
            enable = mkOption {
              type = types.bool;
              default = false;
            };
            ipv4 = mkOption {
              type = types.nullOr types.str;
              default = null;
              description = "Stable Tailscale IPv4 address for services referenced by other hosts.";
            };
          };

          buildCluster = {
            cache.provide = {
              enable = mkOption {
                type = types.bool;
                default = false;
                description = "Whether this host publishes its Nix store to the build cluster.";
              };
              priority = mkOption {
                type = types.ints.positive;
                default = 40;
                description = "Published cache preference; lower values are preferred.";
              };
              port = mkOption {
                type = types.port;
                default = 5000;
                description = "Tailscale-only nix-serve port used by cache and builder providers.";
              };
            };
            builders = {
              provide = {
                enable = mkOption {
                  type = types.bool;
                  default = false;
                  description = "Whether this host accepts remote builds and publishes its resulting store paths.";
                };
                maxJobs = mkOption {
                  type = types.ints.positive;
                  default = 1;
                  description = "Maximum concurrent jobs accepted by this build provider.";
                };
                speedFactor = mkOption {
                  type = types.ints.positive;
                  default = 1;
                  description = "Relative provider speed used by the Nix scheduler; higher values are preferred.";
                };
              };
              use = {
                enable = mkOption {
                  type = types.bool;
                  default = false;
                  description = "Whether this host delegates builds to compatible build-cluster providers.";
                };
                providers = mkOption {
                  type = types.listOf types.str;
                  default = [];
                  description = "Registry host names of the build providers this host may use.";
                };
                localJobs = mkOption {
                  type = types.either types.ints.unsigned (types.enum ["auto"]);
                  default = 0;
                  description = "Maximum local build jobs while using providers; zero makes this host remote-only.";
                };
              };
            };
          };
        };
      });
    };
  };

  config.fleet.stateVersion = "26.05";
}
