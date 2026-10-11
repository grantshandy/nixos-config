{
  config,
  lib,
  pkgs,
  ...
}: {
  imports = [
    ./hardware-configuration.nix
    ../../modules/nixos/bootloader-systemd.nix
    ./headscale.nix
    ./music.nix
    ./photos.nix
  ];

  time.timeZone = "America/Denver";

  users.users.${config.identity.user.name} = {
    isNormalUser = true;
    extraGroups = ["wheel"];
    openssh.authorizedKeys.keys = config.identity.ssh.userKeys;
  };
  security.sudo.wheelNeedsPassword = false;

  documentation.enable = false;
  environment.defaultPackages = lib.mkForce [];
  environment.systemPackages = with pkgs; [vim htop git nodejs];

  # Send kernel messages directly over Ethernet so they survive a userspace or
  # root-filesystem stall. Xenon records these messages in its journal.
  systemd.services.netconsole = {
    description = "Send kernel messages to Xenon via netconsole";
    wantedBy = ["multi-user.target"];
    wants = ["network-online.target"];
    after = ["network-online.target"];
    unitConfig.ConditionPathExists = "/sys/class/net/enp8s0";
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = "${lib.getExe' pkgs.kmod "modprobe"} netconsole netconsole=6665@192.168.86.47/enp8s0,6666@192.168.86.48/ff:ff:ff:ff:ff:ff";
      ExecStop = "${lib.getExe' pkgs.kmod "modprobe"} -r netconsole";
    };
  };

  services.openssh.settings = {
    PasswordAuthentication = lib.mkForce false;
    KbdInteractiveAuthentication = lib.mkForce false;
    PermitRootLogin = lib.mkForce "no";
  };
}
