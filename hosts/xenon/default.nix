{lib, pkgs, ...}: {
  imports = [
    ./hardware-configuration.nix
    ../../modules/nixos/bootloader-systemd.nix
    ../../modules/nixos/desktop
    # ../../modules/nixos/soulseek.nix
  ];

  # networking.networkmanager.wifi.backend = "iwd";
  # networking.networkmanager.wifi.powersave = false;

  boot.binfmt.emulatedSystems = ["aarch64-linux"];

  networking.firewall.allowedUDPPorts = [6666];

  # Persist Radon's netconsole stream in Xenon's journal. View it with:
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
}
