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
  xenonRdpHost = "xenon.ts.${config.identity.homelab.dns}";

  availableVms =
    config.network.hosts
    |> lib.mapAttrsToList (
      hostName: host:
        host.virtualMachines
        |> lib.mapAttrsToList (vmName: vm: {
          inherit hostName host vmName;
          inherit (vm) audioRtpPort title vncPort;
          id = "${hostName}-${vmName}";
        })
    )
    |> lib.concatLists
    |> lib.filter (entry: lib.elem kioskHost entry.host.virtualMachines.${entry.vmName}.kioskClients);

  rtpSourceIp = config.network.hosts.${kioskHost}.tailscale.ipv4;

  remoteHostNameFor = vm:
    if vm.host.tailscale.enable or false
    then "${vm.hostName}.ts.${config.identity.homelab.dns}"
    else vm.hostName;

  knownHostNameFor = vm: let
    remoteHostName = remoteHostNameFor vm;
  in
    if vm.host.ssh.port == 22
    then remoteHostName
    else "[${remoteHostName}]:${toString vm.host.ssh.port}";

  libvirtUriFor = vm: let
    remoteHostName = remoteHostNameFor vm;
  in "qemu+ssh://${kioskUser}@${remoteHostName}:${toString vm.host.ssh.port}/system?keyfile=${sshIdentity}&known_hosts=${knownHosts}";

  mkLaunchVm = vm: let
    remoteHostName = remoteHostNameFor vm;
    libvirtUri = libvirtUriFor vm;
  in
    pkgs.writeShellApplication {
      name = "virtual-machine-kiosk-${vm.id}";
      runtimeInputs = [pkgs.coreutils pkgs.libvirt pkgs.netcat-openbsd pkgs.openssh pkgs.pipewire pkgs.wlvncc];
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

        pw-loopback \
          --name=${lib.escapeShellArg "${vm.id}-rtp-playback"} \
          --capture=${lib.escapeShellArg "${vm.id}-rtp-source"} &
        audio_pid=$!

        cleanup() {
          kill "$audio_pid" "$tunnel_pid" 2>/dev/null || true
          wait "$audio_pid" "$tunnel_pid" 2>/dev/null || true
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

        # Cage has no close shortcut, so retain wlvncc's close button as the
        # explicit disconnect-and-return-to-chooser control.
        wlvncc --shortcut-inhibit 127.0.0.1 ${toString vm.vncPort}
      '';
    };

  mkShutdownVm = vm:
    pkgs.writeShellApplication {
      name = "virtual-machine-shutdown-${vm.id}";
      runtimeInputs = [pkgs.libvirt];
      text = ''
        uri=${lib.escapeShellArg (libvirtUriFor vm)}
        domain=${lib.escapeShellArg vm.vmName}
        state="$(virsh --connect "$uri" domstate "$domain")"

        case "$state" in
          running | paused)
            virsh --connect "$uri" shutdown "$domain"
            ;;
          "shut off") ;;
          *)
            echo "Cannot shut down $domain while it is $state" >&2
            exit 1
            ;;
        esac
      '';
    };

  launchXenonDesktop = pkgs.writeShellApplication {
    name = "connect-to-xenon";
    runtimeInputs = [pkgs.coreutils pkgs.freerdp];
    text = ''
      RDP_USERNAME=""
      RDP_PASSWORD=""
      set -a
      # shellcheck source=/dev/null
      source ${config.age.secrets.gnome-remote-desktop-credentials.path}
      set +a

      umask 077
      args_file="$(mktemp)"
      cleanup() {
        rm -f "$args_file"
      }
      trap cleanup EXIT INT TERM

      printf '%s\n' \
        ${lib.escapeShellArg "/v:${xenonRdpHost}:3389"} \
        "/u:$RDP_USERNAME" \
        "/p:$RDP_PASSWORD" \
        '/cert:tofu' \
        '/f' \
        '+dynamic-resolution' \
        '+clipboard' \
        '/audio-mode:redirect' \
        '/network:auto' \
        >"$args_file"

      ${lib.getExe' pkgs.freerdp "sdl-freerdp"} /args-from:file:"$args_file"
    '';
  };

  vmActions =
    map (vm: {
      inherit vm;
      launch = mkLaunchVm vm;
      shutdown = mkShutdownVm vm;
      connectLabel = "Connect to ${vm.title}";
      shutdownLabel = "Shut down ${vm.title}";
    })
    availableVms;

  menuLabels =
    lib.concatMap (action: [action.connectLabel action.shutdownLabel]) vmActions
    ++ ["Connect to Xenon" "Reboot Krypton" "Power off Krypton"];

  menuCases =
    lib.concatMapStringsSep "\n" (action: ''
      ${lib.escapeShellArg action.connectLabel})
        ${lib.getExe action.launch}
        ;;
      ${lib.escapeShellArg action.shutdownLabel})
        ${lib.getExe action.shutdown}
        ;;
    '')
    vmActions;

  applianceChooser = pkgs.writeShellApplication {
    name = "krypton-appliance-chooser";
    runtimeInputs = [pkgs.systemd pkgs.zenity];
    text = ''
      while true; do
        if ! choice="$(zenity \
          --list \
          --title='Krypton' \
          --text='Choose what Krypton should do' \
          --column='Action' \
          --hide-header \
          --width=640 \
          --height=420 \
          ${lib.concatMapStringsSep " " lib.escapeShellArg menuLabels})"; then
          continue
        fi

        case "$choice" in
          ${menuCases}
          'Connect to Xenon')
            ${lib.getExe launchXenonDesktop}
            ;;
          'Reboot Krypton')
            systemctl reboot
            ;;
          'Power off Krypton')
            systemctl poweroff
            ;;
        esac
      done
    '';
  };

  chooserSession = pkgs.writeShellScript "krypton-appliance-session" ''
    exec ${lib.getExe pkgs.cage} -- ${lib.getExe applianceChooser}
  '';

  knownHostsText = lib.concatMapStringsSep "\n" (vm: "${knownHostNameFor vm} ${config.identity.ssh.hostKeys.${vm.hostName} or ""}") availableVms;
  sshConfigText =
    lib.concatMapStringsSep "\n" (vm: let
      remoteHostName = remoteHostNameFor vm;
    in ''
      Host ${remoteHostName}
        User ${kioskUser}
        Port ${toString vm.host.ssh.port}
        IdentityFile ${sshIdentity}
        IdentitiesOnly yes
        UserKnownHostsFile ${knownHosts}
        StrictHostKeyChecking yes
    '')
    availableVms;
in {
  assertions =
    [
      {
        assertion = availableVms != [];
        message = "Kiosk '${kioskHost}' must have at least one assigned registry VM.";
      }
      {
        assertion = rtpSourceIp != null;
        message = "VM kiosk '${kioskHost}' needs a registry Tailscale IPv4 address for RTP audio.";
      }
    ]
    ++ lib.concatMap (vm: [
      {
        assertion = (config.identity.ssh.hostKeys.${vm.hostName} or "") != "";
        message = "VM host '${vm.hostName}' needs an identity.ssh.hostKeys entry.";
      }
      {
        assertion = vm.host.ssh.enable or false;
        message = "VM host '${vm.hostName}' must enable SSH.";
      }
      {
        assertion = (vm.host.tailscale.ipv4 or null) != null;
        message = "VM host '${vm.hostName}' needs a registry Tailscale IPv4 address for RTP audio.";
      }
    ])
    availableVms;

  hardware.graphics.enable = true;

  services.pipewire = {
    enable = true;
    alsa.enable = true;
    extraConfig.pipewire = lib.listToAttrs (map (vm:
      lib.nameValuePair "90-${vm.id}-rtp" {
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
                "node.name" = "${vm.id}-rtp-source";
                "node.description" = "${vm.title} RTP audio";
              };
            };
          }
        ];
      })
    availableVms);
  };
  security.rtkit.enable = true;

  # This hidden system account owns the chooser and VM sessions. There is no
  # interactive login at the appliance UI, and SSH password login stays disabled.
  users.users.${kioskUser} = {
    isSystemUser = true;
    group = kioskUser;
    home = kioskStateDir;
    createHome = false;
    extraGroups = ["audio" "input" "render" "video"];
  };
  users.groups.${kioskUser} = {};

  age.secrets.gnome-remote-desktop-credentials = {
    file = ../../secrets/gnome-remote-desktop-credentials.age;
    owner = kioskUser;
    group = kioskUser;
    mode = "0400";
  };

  environment.etc = {
    "${kioskUser}/known_hosts".text = knownHostsText;
    "${kioskUser}/ssh_config".text = sshConfigText;
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

  # greetd provides the logind session, but the appliance chooser itself has no
  # authentication layer. Cage stays alive while Zenity, wlvncc, and VM actions
  # take turns as its client.
  services.greetd = {
    enable = true;
    settings = {
      initial_session = {
        command = chooserSession;
        user = kioskUser;
      };
      default_session = {
        command = chooserSession;
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
