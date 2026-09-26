{
  inputs,
  pkgs,
  lib,
  config,
  ...
}: {
  imports = [
    "${inputs.nixpkgs}/nixos/modules/installer/sd-card/sd-image.nix"
    inputs.nixos-hardware.nixosModules.raspberry-pi-4
  ];

  hardware = {
    wirelessRegulatoryDatabase = true;
    raspberry-pi.firmware = {
      enable = true;
      uboot.enable = true;
    };
  };

  boot = {
    kernelPackages = lib.mkForce pkgs.linuxPackages;
    kernelParams = ["module_blacklist=vc4,v3d"];
  };

  fileSystems."/mnt/media" = {
    device = "/dev/disk/by-uuid/ffb3b356-8c16-4d31-9a27-5a71e275769c";
    fsType = "ext4";
    options = [
      "noatime"
      "nofail"
      "x-systemd.device-timeout=10"
    ];
  };

  users.groups.media = {};
  users.users.${config.identity.user.name}.extraGroups = [ "media" ];
  systemd.tmpfiles.rules = [
    "z /mnt/media 2775 root media -"
  ];

  sdImage.populateRootCommands = ''
    mkdir -p ./files/boot
    ${config.boot.loader.generic-extlinux-compatible.populateCmd} -c ${config.system.build.toplevel} -d ./files/boot
  '';
}
