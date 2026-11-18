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
          inherit (vm) audioRtpPort title vncPort;
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
      audioRtpPort = 46000;
      vncPort = 5901;
      host = {
        ssh.port = 22;
        tailscale = {
          enable = false;
          ipv4 = null;
        };
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
  rtpSourceIp = config.network.hosts.${kioskHost}.tailscale.ipv4;
  rtpSenderIp = vm.host.tailscale.ipv4 or null;

  launchVm = pkgs.writeShellApplication {
    name = "virtual-machine-kiosk";
    runtimeInputs = [pkgs.coreutils pkgs.libvirt pkgs.netcat-openbsd pkgs.openssh pkgs.wlvncc];
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

      ssh \
        -N \
        -T \
        -o ExitOnForwardFailure=yes \
        -L ${toString vm.vncPort}:127.0.0.1:${toString vm.vncPort} \
        ${lib.escapeShellArg "${kioskUser}@${remoteHostName}"} &
      tunnel_pid=$!

      cleanup() {
        kill "$tunnel_pid" 2>/dev/null || true
        wait "$tunnel_pid" 2>/dev/null || true
      }
      trap cleanup EXIT INT TERM

      for _ in $(seq 1 50); do
        if nc -z 127.0.0.1 ${toString vm.vncPort}; then
          break
        fi
        if ! kill -0 "$tunnel_pid" 2>/dev/null; then
          echo "VNC SSH tunnel exited before becoming ready" >&2
          exit 1
        fi
        sleep 0.1
      done

      wlvncc --no-decorations --shortcut-inhibit 127.0.0.1 ${toString vm.vncPort}
    '';
  };

  kioskSession = pkgs.writeShellScript "virtual-machine-kiosk-session" ''
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
    {
      assertion = rtpSourceIp != null;
      message = "VM kiosk '${kioskHost}' needs a registry Tailscale IPv4 address for RTP audio.";
    }
    {
      assertion = rtpSenderIp != null;
      message = "VM host '${vm.hostName}' needs a registry Tailscale IPv4 address for RTP audio.";
    }
  ];

  hardware.graphics.enable = true;

  services.pipewire = {
    enable = true;
    alsa.enable = true;
    extraConfig.pipewire."90-${vm.vmName}-rtp" = {
      "context.modules" = [
        {
          name = "libpipewire-module-rtp-source";
          args = {
            "source.ip" = "0.0.0.0";
            "source.port" = vm.audioRtpPort;
            "node.always-process" = true;
            "stream.may-pause" = false;
            "audio.format" = "S16BE";
            "audio.rate" = 48000;
            "audio.channels" = 2;
            "audio.position" = ["FL" "FR"];
            "stream.props" = {
              "media.class" = "Audio/Source";
              "node.name" = "${vm.vmName}-rtp-source";
              "node.description" = "${vm.title} RTP audio";
            };
          };
        }
      ];
    };
  };
  security.rtkit.enable = true;

  systemd.user.services.vm-rtp-audio = {
    description = "Play the VM's PipeWire RTP audio stream";
    wantedBy = ["default.target" "pipewire.service"];
    after = ["pipewire.service" "wireplumber.service"];
    wants = ["pipewire.service" "wireplumber.service"];
    unitConfig.ConditionUser = kioskUser;
    serviceConfig = {
      ExecStart = "${lib.getExe' pkgs.pipewire "pw-loopback"} --name=${vm.vmName}-rtp-playback --capture=${vm.vmName}-rtp-source";
      Restart = "always";
      RestartSec = 1;
    };
  };

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

  # virsh and the VNC tunnel share this strict per-user SSH configuration.
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

  # greetd creates a logind session, then Cage exposes only wlvncc's Wayland
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
    serviceConfig = {
      Restart = "always";
      RestartSec = 1;
    };
  };

  boot = {
    kernelParams = ["quiet" "loglevel=3" "systemd.show_status=auto" "udev.log_level=3" "vt.global_cursor_default=0"];
    loader.timeout = 0;
    plymouth.enable = true;
  };
}
