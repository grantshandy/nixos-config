# The bulk storage pool the media services share.
#
# The directory layout is derived once at the flake level from the owning host's
# `mediaRoot`, so each service file names its own directory rather than
# rebuilding the whole tree from an untyped `radonMediaRoot` argument. The mount
# and device unit names have to come from the host's own `fileSystems`, so those
# are a small readOnly NixOS option instead.
{
  config,
  lib,
  ...
}: let
  inherit (lib) mkOption types;

  mediaHosts =
    config.fleet.hosts
    |> lib.filterAttrs (_: host: lib.elem "media" host.tags)
    |> lib.attrNames;

  host =
    if lib.length mediaHosts == 1
    then lib.head mediaHosts
    else throw "Exactly one host must be tagged \"media\", found: ${lib.concatStringsSep ", " mediaHosts}.";

  root = config.fleet.hosts.${host}.mediaRoot;
  lidarr = "${root}/lidarr";
in {
  options.fleet.media =
    {
      host = mkOption {
        type = types.str;
        readOnly = true;
        description = "Host that owns the media pool, derived from the \"media\" tag.";
      };

      root = mkOption {
        type = types.path;
        readOnly = true;
      };
    }
    // lib.genAttrs [
      # Lidarr owns the canonical library and its download staging directories;
      # Navidrome reads the library and slskd writes the downloads.
      "library"
      "downloads"
      "incomplete"
      "lidarrDir"
      "lidarrConfig"
      "navidromeData"
      "legacyMusic"
      "slskdDir"
    ] (_:
      mkOption {
        type = types.path;
        readOnly = true;
      });

  config = {
    fleet.media = {
      inherit host root;
      lidarrDir = lidarr;
      lidarrConfig = "${lidarr}/config";
      library = "${lidarr}/library";
      downloads = "${lidarr}/downloads";
      incomplete = "${lidarr}/incomplete";
      navidromeData = "${root}/navidrome";
      legacyMusic = "${root}/music";
      slskdDir = "${root}/slskd";
    };

    fleet.aspects.media-pool.hosts = [host];

    flake.modules.nixos.media-pool = {
      config,
      utils,
      ...
    }: {
      options.mediaPool = {
        mountUnit = mkOption {
          type = types.str;
          readOnly = true;
          description = "systemd unit name of the media pool's mount.";
        };
        deviceUnit = mkOption {
          type = types.str;
          readOnly = true;
          description = ''
            systemd unit name of the backing device. Services bind to the mount
            and are wanted by the device, so hot-plugging the drive brings them
            back without manual intervention.
          '';
        };
      };

      config.mediaPool = {
        mountUnit = "${utils.escapeSystemdPath root}.mount";
        deviceUnit = "${utils.escapeSystemdPath config.fileSystems.${root}.device}.device";
      };
    };
  };
}
