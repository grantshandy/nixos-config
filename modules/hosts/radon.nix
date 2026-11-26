# The media and CI server. Holds the bulk storage pool and the fleet's fastest
# builder, and fronts its own services behind a local reverse proxy.
let
  proxyPort = 8080;
  mediaRoot = "/mnt/media";
in {
  fleet.hosts.radon = {
    system = "x86_64-linux";
    tags = ["server" "media" "ci"];

    ssh = {
      enable = true;
      port = 22;
    };
    tailscale.enable = true;
    inherit proxyPort;
    inherit mediaRoot;

    buildCluster = {
      cache.provide = {
        enable = true;
        priority = 10;
      };
      builders.provide = {
        enable = true;
        maxJobs = 1;
        speedFactor = 50;
      };
    };
  };

  flake.modules.nixos.radon = {
    config,
    lib,
    pkgs,
    ...
  }: {
    imports = [(import ./_hardware/radon.nix {inherit mediaRoot;})];

    time.timeZone = "America/Denver";

    users.users.${config.identity.user.name} = {
      isNormalUser = true;
      extraGroups = ["wheel"];
    };
    security.sudo.wheelNeedsPassword = false;

    networking.firewall.interfaces.enp8s0.allowedTCPPorts = [
      proxyPort
    ];

    nix = {
      gc = {
        automatic = true;
        dates = "weekly";
        options = "--delete-older-than 14d";
      };

      settings = {
        min-free = 10 * 1024 * 1024 * 1024;
        max-free = 20 * 1024 * 1024 * 1024;
      };

      optimise = {
        automatic = true;
        dates = ["weekly"];
      };
    };

    documentation.enable = false;
    environment.defaultPackages = lib.mkForce [];
    environment.systemPackages = with pkgs; [vim htop btop git nodejs];

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
  };
}
