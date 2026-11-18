{
  config,
  lib,
  pkgs,
  ...
}: let
  kioskHost = config.networking.hostName;
  kioskUser = "vm-kiosk";
  kioskStateDir = "/var/lib/${kioskUser}";
  sshIdentity = "${kioskStateDir}/id_ed25519";
  knownHosts = "/etc/${kioskUser}/known_hosts";

  availableVms =
    config.network.hosts
    |> lib.mapAttrsToList (
      hostName: host:
        host.virtualMachines
        |> lib.mapAttrsToList (vmName: vm: {
          inherit hostName host vmName;
          inherit (vm) title;
        })
    )
    |> lib.concatLists
    |> lib.filter (entry: lib.elem kioskHost entry.host.virtualMachines.${entry.vmName}.kioskClients);

  vm =
    if lib.length availableVms == 1
    then lib.head availableVms
    else {
      hostName = "invalid";
      vmName = "invalid";
      title = "Invalid VM registry configuration";
      host = {
        ssh.port = 22;
        virtualMachines = {};
      };
    };

  remoteHostKey = config.identity.ssh.hostKeys.${vm.hostName} or "";
  remoteHostName =
    if vm.host.tailscale.enable or false
    then "${vm.hostName}.ts.${config.identity.homelab.dns}"
    else vm.hostName;
  knownHostName =
    if vm.host.ssh.port == 22
    then remoteHostName
    else "[${remoteHostName}]:${toString vm.host.ssh.port}";
  libvirtUri = "qemu+ssh://${kioskUser}@${remoteHostName}:${toString vm.host.ssh.port}/system?keyfile=${sshIdentity}&known_hosts=${knownHosts}";

  launchVm = pkgs.writeShellApplication {
    name = "virtual-machine-kiosk";
    runtimeInputs = [pkgs.coreutils pkgs.gnugrep pkgs.libvirt pkgs.openssh pkgs.virt-viewer];
    text = ''
      uri=${lib.escapeShellArg libvirtUri}
      domain=${lib.escapeShellArg vm.vmName}

      state=""
      for _ in $(seq 1 30); do
        if state="$(virsh --connect "$uri" domstate "$domain" 2>/dev/null)"; then
          break
        fi
        sleep 2
      done

      case "$state" in
        running) ;;
        paused)
          virsh --connect "$uri" resume "$domain"
          ;;
        "shut off" | "")
          virsh --connect "$uri" start "$domain"
          ;;
        *)
          echo "Cannot launch $domain while it is $state" >&2
          exit 1
          ;;
      esac

      exec virt-viewer \
        --connect "$uri" \
        --wait \
        --reconnect \
        --full-screen \
        --kiosk \
        --kiosk-quit=on-disconnect \
        "$domain"
    '';
  };

  kioskSession = pkgs.writeShellScript "virtual-machine-kiosk-session" ''
    export GDK_BACKEND=wayland
    exec ${lib.getExe pkgs.cage} -- ${lib.getExe launchVm}
  '';
in {
  assertions = [
    {
      assertion = lib.length availableVms == 1;
      message = "Kiosk '${kioskHost}' must have exactly one assigned registry VM; found ${toString (lib.length availableVms)}.";
    }
    {
      assertion = remoteHostKey != "";
      message = "VM host '${vm.hostName}' needs an identity.ssh.hostKeys entry.";
    }
    {
      assertion = vm.host.ssh.enable or false;
      message = "VM host '${vm.hostName}' must enable SSH.";
    }
  ];

  hardware.graphics.enable = true;

  services.pipewire = {
    enable = true;
    alsa.enable = true;
    pulse.enable = true;
  };
  security.rtkit.enable = true;

  users.users.${kioskUser} = {
    isSystemUser = true;
    group = kioskUser;
    home = kioskStateDir;
    createHome = false;
    extraGroups = ["audio" "input" "render" "video"];
  };
  users.groups.${kioskUser} = {};

  environment.etc = {
    "${kioskUser}/known_hosts".text = ''
      ${knownHostName} ${remoteHostKey}
    '';
    "${kioskUser}/ssh_config".text = ''
      Host ${remoteHostName}
        User ${kioskUser}
        Port ${toString vm.host.ssh.port}
        IdentityFile ${sshIdentity}
        IdentitiesOnly yes
        UserKnownHostsFile ${knownHosts}
        StrictHostKeyChecking yes
    '';
  };

  # virt-viewer opens separate SSH processes for its SPICE channels. Unlike the
  # libvirt control connection, those processes do not inherit the URI's
  # keyfile and known_hosts query parameters, so they use this per-user config.
  systemd.tmpfiles.rules = [
    "d ${kioskStateDir} 0700 ${kioskUser} ${kioskUser} -"
    "d ${kioskStateDir}/.ssh 0700 ${kioskUser} ${kioskUser} -"
    "L+ ${kioskStateDir}/.ssh/config - - - - /etc/${kioskUser}/ssh_config"
  ];

  # Reuse Krypton's existing host identity for unattended, registry-authorized
  # access to Radon's dedicated libvirt kiosk account.
  systemd.services.vm-kiosk-identity = {
    description = "Install the VM kiosk SSH identity";
    wantedBy = ["multi-user.target"];
    before = ["greetd.service"];
    serviceConfig.Type = "oneshot";
    script = ''
      ${lib.getExe' pkgs.coreutils "install"} \
        --mode=0400 \
        --owner=${kioskUser} \
        --group=${kioskUser} \
        /etc/ssh/ssh_host_ed25519_key \
        ${sshIdentity}
    '';
  };

  # greetd creates a logind session, then Cage exposes only virt-viewer's SPICE
  # surface. If the viewer exits, greetd starts the kiosk session again.
  services.greetd = {
    enable = true;
    settings = {
      initial_session = {
        command = kioskSession;
        user = kioskUser;
      };
      default_session = {
        command = kioskSession;
        user = kioskUser;
      };
    };
  };

  systemd.services.greetd = {
    wants = ["network-online.target"];
    requires = ["vm-kiosk-identity.service"];
    after = ["network-online.target" "vm-kiosk-identity.service"];
  };

  boot = {
    kernelParams = ["quiet" "loglevel=3" "systemd.show_status=auto" "udev.log_level=3" "vt.global_cursor_default=0"];
    loader.timeout = 0;
    plymouth.enable = true;
  };
}
