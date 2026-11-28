# Mirrors the media pool onto an external USB drive once a day.
{config, ...}: {
  fleet.aspects.media-backup.hosts = [config.fleet.media.host];

  flake.modules.nixos.media-backup =
    ({mediaRoot}: {
      lib,
      pkgs,
      ...
    }: let
      backupDevice = "/dev/disk/by-uuid/64fc1f78-364d-4e91-a9fc-5e7c20c3afce";
      backupMountPoint = "/run/media-backup";
      backupExcludes = [
        "/gitlab-runner-builds"
        "/gitlab-runner-cache"
        "/lost+found"
      ];
    in {
      # Mirrors mediaRoot onto an external USB backup drive once a day.
      # The drive is mounted only for the sync. A separate guard spins it down
      # after boot and periodically in case USB enumeration or another probe wakes it.

      # The USB backup drive (Seagate BUP Slim) lies about its power state and
      # ignores ATA STANDBY under the UAS driver; force the older usb-storage
      # driver for it so hdparm can reliably spin it down between backups.
      boot.kernelParams = ["usb-storage.quirks=0bc2:ab24:u"];

      systemd.services.media-backup = {
        description = "Back up ${mediaRoot} to external USB drive";
        unitConfig.ConditionPathExists = backupDevice;
        serviceConfig = {
          Type = "oneshot";
          IOSchedulingClass = "idle";
          Nice = 19;
        };
        path = [pkgs.rsync pkgs.util-linux pkgs.hdparm];
        script = ''
          exec 9>/run/media-backup.lock
          flock 9

          mkdir -p ${backupMountPoint}
          mount -t ext4 -o noatime ${backupDevice} ${backupMountPoint}
          disk="/dev/$(lsblk -no pkname "$(readlink -f ${backupDevice})")"
          trap 'umount ${backupMountPoint}; hdparm -y "$disk"' EXIT

          rsync -a --delete -i \
            ${lib.concatMapStringsSep " " (p: "--exclude=${p}") backupExcludes} \
            ${mediaRoot}/ ${backupMountPoint}/ | grep -v '^$'
        '';
      };

      systemd.timers.media-backup = {
        description = "Daily timer for media-backup";
        wantedBy = ["timers.target"];
        timerConfig = {
          OnCalendar = "03:00";
          Persistent = false;
        };
      };

      systemd.services.media-backup-standby = {
        description = "Keep the unmounted media backup drive in standby";
        unitConfig.ConditionPathExists = backupDevice;
        serviceConfig.Type = "oneshot";
        path = [pkgs.systemd pkgs.util-linux pkgs.hdparm];
        script = ''
          exec 9>/run/media-backup.lock
          flock --nonblock 9 || exit 0

          # Avoid spinning down a manually mounted drive as well.
          if systemctl is-active --quiet media-backup.service \
            || findmnt --mountpoint ${backupMountPoint} >/dev/null; then
            exit 0
          fi

          disk="/dev/$(lsblk -no pkname "$(readlink -f ${backupDevice})")"
          hdparm -y "$disk"
        '';
      };

      systemd.timers.media-backup-standby = {
        description = "Periodically spin down the unmounted media backup drive";
        wantedBy = ["timers.target"];
        timerConfig = {
          OnBootSec = "30s";
          OnUnitInactiveSec = "5m";
          AccuracySec = "30s";
        };
      };
    }) {
      mediaRoot = config.fleet.media.root;
    };
}
