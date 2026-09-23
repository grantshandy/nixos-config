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

  sdImage.populateRootCommands = ''
    mkdir -p ./files/boot
    ${config.boot.loader.generic-extlinux-compatible.populateCmd} -c ${config.system.build.toplevel} -d ./files/boot
  '';
}
