# Strips documentation, locales, and other bulk off machines that are
# deliberately minimal.
{
  fleet.aspects.lean.tags = ["minimal"];
  flake.modules.nixos.lean = {lib, ...}: {
    # Krypton is managed remotely with Colmena and does not need local installer,
    # VM-building, or option-inspection tools in its system closure.
    system.tools = {
      nixos-option.enable = false;
      nixos-build-vms.enable = false;
      nixos-install.enable = false;
      nixos-enter.enable = false;
    };

    documentation = {
      enable = false;
      man.enable = false;
      nixos.enable = false;
    };

    fonts.fontconfig.enable = false;
    services.lvm.enable = false;
    boot.bcache.enable = false;
    systemd.oomd.enable = false;

    systemd.suppressedSystemUnits = [
      "systemd-importd.service"
      "sys-kernel-config.mount"
    ];

    security.pam.services.su.forwardXAuth = lib.mkForce false;

    # Socket activation avoids keeping an idle sshd listener resident while
    # preserving normal SSH and Colmena access.
    services.openssh.startWhenNeeded = true;

    # Krypton reaches its reverse-proxy backends over stable tailnet DNS names,
    # so it does not need an mDNS responder or nss-mdns integration.
    services.avahi = {
      enable = lib.mkForce false;
      nssmdns4 = lib.mkForce false;
      openFirewall = lib.mkForce false;
    };

    # A headless appliance only needs its primary local console.
    systemd.services = {
      "getty@tty2".enable = false;
      "getty@tty3".enable = false;
      "getty@tty4".enable = false;
      "getty@tty5".enable = false;
      "getty@tty6".enable = false;
    };

    environment.variables = {
      GC_INITIAL_HEAP_SIZE = "33554432";
      GC_FREE_SPACE_DIVISOR = "8";
      GC_FORCE_UNMAP_ON_GCOLLECT = "1";
    };

    services.journald.extraConfig = ''
      SystemMaxUse=50M
    '';
  };
}
