{
  config,
  lib,
  pkgs,
  ...
}: let
  radonMediaRoot = "/mnt/media";
  radonEndpoints = lib.mapAttrs (_: service: let
    host = "${lib.optionalString (service.subdomain != null) "${service.subdomain}."}${config.identity.homelab.dns}";
  in
    service
    // {
      inherit host;
      url = "https://${host}${service.path}";
      basePath = lib.removeSuffix "/" service.path;
    })
  config.network.hosts.radon.publicWebServices;
in {
  _module.args = {inherit radonMediaRoot radonEndpoints;};

  imports = [
    ./hardware-configuration.nix
    ../../modules/nixos/bootloader-systemd.nix
    ./gitlab-runner.nix
    ./endpoints/auth.nix
    ./endpoints/cockpit.nix
    ./endpoints/directory.nix
    ./endpoints/headscale.nix
    ./endpoints/music.nix
    ./endpoints/photos.nix
  ];

  time.timeZone = "America/Denver";

  users.users.${config.identity.user.name} = {
    isNormalUser = true;
    extraGroups = ["wheel"];
  };
  security.sudo.wheelNeedsPassword = false;

  services.caddy = {
    enable = true;
    globalConfig = ''
      auto_https disable_redirects
    '';
  };
  networking.firewall.allowedTCPPorts = [443];

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
}
