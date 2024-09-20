{ ... }: {
  fileSystems."/mnt/shared" =
    {
      device = "/dev/disk/by-uuid/C62F-33E3";
      fsType = "auto";
      options = [ "nosuid" "nodev" "nofail" "x-gvfs-show" ];
    };
}
