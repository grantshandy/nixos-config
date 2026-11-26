# systemd-boot on EFI. Hosts opt in; the hardware decides.
{
  fleet.aspects.bootloader-systemd.default = true;
  flake.modules.nixos.bootloader-systemd = {...}: {
    boot.loader = {
      systemd-boot = {
        enable = true;
        configurationLimit = 1;
      };
      efi.canTouchEfiVariables = true;
    };
  };
}
