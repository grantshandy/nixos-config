# An aspect is a named feature that may have a NixOS half, a Home Manager half,
# or both. This declares how an aspect enrolls itself onto hosts, so a feature
# file decides where it belongs instead of each host listing its imports.
{lib, ...}: let
  inherit (lib) mkOption types;
in {
  options.fleet.aspects = mkOption {
    default = {};
    description = "Enrollment rules for aspects published under flake.modules.<class>.";
    type = types.attrsOf (types.submodule {
      options = {
        default = mkOption {
          type = types.bool;
          default = false;
          description = "Whether every host in the fleet receives this aspect.";
        };
        hosts = mkOption {
          type = types.listOf types.str;
          default = [];
          description = "Host names that receive this aspect.";
        };
        tags = mkOption {
          type = types.listOf types.str;
          default = [];
          description = "Hosts carrying any of these tags receive this aspect.";
        };
      };
    });
  };
}
