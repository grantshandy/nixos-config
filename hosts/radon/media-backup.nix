{
  lib,
  pkgs,
  radonMediaRoot,
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
  # Mirrors radonMediaRoot onto an external USB backup drive once a day.
  # The drive is only mounted for the duration of the sync and otherwise left
  # alone so its own idle timer can spin it down, to minimize power-on hours.

  # The USB backup drive (Seagate BUP Slim) lies about its power state and
  # ignores ATA STANDBY under the UAS driver; force the older usb-storage
  # driver for it so hdparm can reliably spin it down between backups.
  boot.kernelParams = ["usb-storage.quirks=0bc2:ab24:u"];

  systemd.services.media-backup = {
    description = "Back up ${radonMediaRoot} to external USB drive";
    unitConfig.ConditionPathExists = backupDevice;
    serviceConfig = {
      Type = "oneshot";
      IOSchedulingClass = "idle";
      Nice = 19;
    };
    path = [pkgs.rsync pkgs.util-linux pkgs.hdparm];
    script = ''
      mkdir -p ${backupMountPoint}
      mount -t ext4 -o noatime ${backupDevice} ${backupMountPoint}
      disk="/dev/$(lsblk -no pkname "$(readlink -f ${backupDevice})")"
      trap 'umount ${backupMountPoint}; hdparm -y "$disk"' EXIT

      rsync -a --delete -i \
        ${lib.concatMapStringsSep " " (p: "--exclude=${p}") backupExcludes} \
        ${radonMediaRoot}/ ${backupMountPoint}/ | grep -v '^$'
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
}
