# Workstation and the fleet's build machine; also runs the local LLM.
{
  fleet.hosts.xenon = {
    system = "x86_64-linux";
    tags = ["desktop" "llm"];

    ssh = {
      enable = true;
      port = 4321;
    };
    tailscale.enable = true;
    extraStorageRoot = "/var/lib/extra-storage";
    buildCluster = {
      cache.provide = {
        enable = true;
        priority = 20;
      };
      builders.provide = {
        enable = true;
        maxJobs = 3;
        speedFactor = 100;
      };
    };
  };

  flake.modules.nixos.xenon = {
    lib,
    pkgs,
    ...
  }: {
    imports = [./_hardware/xenon.nix];

    boot.binfmt.emulatedSystems = ["aarch64-linux"];

    networking.firewall.allowedUDPPorts = [6666];

    # Persist radon's netconsole stream in xenon's journal. View it with:
    # journalctl -u radon-netconsole-receiver.service
    systemd.services.radon-netconsole-receiver = {
      description = "Receive netconsole messages from Radon";
      wantedBy = ["multi-user.target"];
      after = ["network.target"];
      serviceConfig = {
        ExecStart = "${lib.getExe pkgs.netcat-openbsd} -d -u -k -l 6666";
        Restart = "always";
        RestartSec = "1s";
        DynamicUser = true;
        ProtectSystem = "strict";
        ProtectHome = true;
        PrivateTmp = true;
      };
    };
  };
}
