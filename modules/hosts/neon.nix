# Lenovo IdeaPad 5 15ARE05. Minimal console-only fleet member.
{
  fleet.hosts.neon = {
    system = "x86_64-linux";
    tags = ["lean" "battery"];

    ssh = {
      enable = true;
      port = 22;
    };
    tailscale.enable = true;
    extraStorageRoot = "/var/lib/extra-storage";
    buildCluster.cache.provide = {
      enable = true;
      priority = 15;
    };
  };

  flake.modules.nixos.neon = {modulesPath, ...}: {
    imports = [
      (modulesPath + "/profiles/minimal.nix")
      ./_hardware/neon.nix
    ];

    # The built-in panel has been physically removed. Disabling only its DRM
    # connector avoids phantom-display handling while leaving HDMI/DP usable.
    boot.kernelParams = ["video=eDP-1:d"];

    # Treat the machine as an always-on headless appliance regardless of the
    # laptop lid sensor or whether external power/display detection changes.
    services.logind.settings.Login = {
      HandleLidSwitch = "ignore";
      HandleLidSwitchExternalPower = "ignore";
      HandleLidSwitchDocked = "ignore";
      IdleAction = "ignore";
    };

    systemd.targets = {
      sleep.enable = false;
      suspend.enable = false;
      hibernate.enable = false;
      hybrid-sleep.enable = false;
    };

    networking = {
      useDHCP = true;
      wireless = {
        enable = true;
        networks."SummerHill_NET".pskRaw = "dca38956c6dbd03a98a8cdc48304b2566ab3b24161c6e47767c63de808c6d674";
      };
    };

    services.openssh.settings.PasswordAuthentication = false;
    security.sudo.wheelNeedsPassword = false;
  };
}
