{
  config,
  lib,
  pkgs,
  ...
}: let
  host = config.network.hosts.${config.networking.hostName};
  vmName = "windows-xp";
  vm = host.virtualMachines.${vmName};
  kioskUser = "vm-kiosk";
  kioskClientsWithHostKeys =
    lib.filter (
      client: builtins.hasAttr client config.identity.ssh.hostKeys
    )
    vm.kioskClients;
  kioskClientName =
    if lib.length vm.kioskClients == 1
    then lib.head vm.kioskClients
    else "invalid";
  kioskClient = config.network.hosts.${kioskClientName} or {};
  rtpSourceIp = host.tailscale.ipv4 or null;
  rtpDestinationIp = kioskClient.tailscale.ipv4 or null;
  vmStateDir = "/var/lib/libvirt/images/${vmName}";
  vmDisk = "${vmStateDir}/system.qcow2";

  qxlXpDriver = pkgs.fetchzip {
    url = "https://www.spice-space.org/download/windows/qxl/qxl-0.1-16/qxl_xp_x86.zip";
    hash = "sha256-Le8+9vFBVjmqvwrpdfAJrr0GAleSpUCvWMVNmJbcdW0=";
    stripRoot = false;
  };
  qxlXpDriverIso = pkgs.runCommand "qxl-xp-x86-driver.iso" {nativeBuildInputs = [pkgs.xorriso];} ''
    xorrisofs -quiet -J -R -V QXL_XP_DRIVER -o "$out" ${qxlXpDriver}
  '';

  domainXmlSource = pkgs.writeText "${vmName}-domain.xml" ''
    <domain type="kvm">
      <name>${vmName}</name>
      <uuid>5af2d86d-cf0c-4e91-95a6-f17cb5dcdb3b</uuid>
      <title>${lib.escapeXML vm.title}</title>
      <memory unit="MiB">1024</memory>
      <currentMemory unit="MiB">1024</currentMemory>
      <vcpu placement="static">2</vcpu>

      <os>
        <type arch="x86_64" machine="pc-i440fx-9.2">hvm</type>
        <boot dev="hd"/>
        <bootmenu enable="yes"/>
      </os>

      <features>
        <acpi/>
        <apic/>
      </features>
      <cpu mode="host-passthrough" check="none" migratable="off"/>
      <clock offset="localtime">
        <timer name="rtc" tickpolicy="catchup"/>
        <timer name="pit" tickpolicy="delay"/>
        <timer name="hpet" present="no"/>
      </clock>

      <on_poweroff>destroy</on_poweroff>
      <on_reboot>restart</on_reboot>
      <on_crash>preserve</on_crash>

      <devices>
        <disk type="file" device="disk">
          <driver name="qemu" type="qcow2" cache="writeback" discard="unmap"/>
          <source file="${vmDisk}"/>
          <target dev="hda" bus="ide"/>
        </disk>
        <disk type="file" device="cdrom">
          <driver name="qemu" type="raw"/>
          <source file="${qxlXpDriverIso}"/>
          <target dev="hdc" bus="ide"/>
          <readonly/>
        </disk>
        <controller type="ide" index="0"/>
        <controller type="usb" index="0" model="piix3-uhci"/>

        <!-- User-mode networking keeps unsupported Windows XP off the LAN. -->
        <interface type="user">
          <model type="rtl8139"/>
        </interface>

        <input type="mouse" bus="ps2"/>
        <input type="keyboard" bus="ps2"/>
        <input type="tablet" bus="usb"/>

        <graphics type="vnc" port="${toString vm.vncPort}" autoport="no" sharePolicy="allow-exclusive">
          <listen type="address" address="127.0.0.1"/>
          <audio id="1"/>
        </graphics>
        <!-- Retain SPICE as a recovery console while Krypton's kiosk uses VNC. -->
        <graphics type="spice" autoport="yes">
          <listen type="address" address="127.0.0.1"/>
          <image compression="auto_glz"/>
          <jpeg compression="auto"/>
          <zlib compression="auto"/>
          <streaming mode="filter"/>
          <gl enable="no"/>
        </graphics>
        <video>
          <model type="qxl" ram="65536" vram="65536" vgamem="16384" heads="1" primary="yes"/>
        </video>
        <audio id="1" type="pipewire" runtimeDir="/run/pipewire">
          <output name="${vmName}-rtp" streamName="${lib.escapeXML vm.title}" latency="20000"/>
        </audio>
        <sound model="ac97">
          <audio id="1"/>
        </sound>

        <memballoon model="none"/>
      </devices>
    </domain>
  '';

  # Fail the Nix build rather than deployment if the domain stops conforming to
  # the libvirt schema shipped by this configuration.
  domainXml = pkgs.runCommand "${vmName}-domain.xml" {nativeBuildInputs = [pkgs.libvirt];} ''
    cp ${domainXmlSource} "$out"
    virt-xml-validate "$out" domain
  '';

  defineDomain = pkgs.writeShellScript "define-${vmName}-domain" ''
    set -eu
    virsh=${lib.escapeShellArg (lib.getExe' pkgs.libvirt "virsh")}
    "$virsh" --connect qemu:///system define ${lib.escapeShellArg domainXml}
    "$virsh" --connect qemu:///system autostart --disable ${lib.escapeShellArg vmName}
  '';
in {
  virtualisation.libvirtd = {
    enable = true;
    qemu = {
      package = pkgs.qemu_kvm;
      runAsRoot = false;
      swtpm.enable = false;
    };
  };

  services.pipewire = {
    enable = true;
    systemWide = true;
    extraConfig.pipewire."90-${vmName}-rtp" = {
      "context.modules" = [
        {
          name = "libpipewire-module-rtp-sink";
          args = {
            "source.ip" = rtpSourceIp;
            "destination.ip" = rtpDestinationIp;
            "destination.port" = vm.audioRtpPort;
            "local.ifname" = "tailscale0";
            "net.mtu" = 1200;
            "sess.min-ptime" = 2;
            "sess.max-ptime" = 10;
            "rtp.framecount" = 240;
            "sess.name" = vm.title;
            "audio.format" = "S16BE";
            "audio.rate" = 48000;
            "audio.channels" = 2;
            "audio.position" = ["FL" "FR"];
            "stream.props" = {
              "node.name" = "${vmName}-rtp";
              "node.description" = "${vm.title} RTP audio";
              "media.class" = "Audio/Sink";
              "node.always-process" = true;
            };
          };
        }
      ];
    };
  };
  security.rtkit.enable = true;

  users.users.${config.identity.user.name}.extraGroups = ["libvirtd"];
  users.users.qemu-libvirtd.extraGroups = ["pipewire"];
  users.users.${kioskUser} = {
    isSystemUser = true;
    group = kioskUser;
    extraGroups = ["libvirtd"];
    shell = pkgs.bashInteractive;
    openssh.authorizedKeys.keys =
      map (
        client: ''no-agent-forwarding,no-pty,no-user-rc,no-X11-forwarding,permitopen="127.0.0.1:${toString vm.vncPort}" ${config.identity.ssh.hostKeys.${client}}''
      )
      kioskClientsWithHostKeys;
  };
  users.groups.${kioskUser} = {};

  assertions =
    [
      {
        assertion = lib.length vm.kioskClients == 1;
        message = "VM '${vmName}' needs exactly one kiosk client for unicast RTP audio.";
      }
      {
        assertion = rtpSourceIp != null;
        message = "VM host '${config.networking.hostName}' needs a registry Tailscale IPv4 address for RTP audio.";
      }
      {
        assertion = rtpDestinationIp != null;
        message = "VM kiosk '${kioskClientName}' needs a registry Tailscale IPv4 address for RTP audio.";
      }
    ]
    ++ map (client: {
      assertion = builtins.hasAttr client config.identity.ssh.hostKeys;
      message = "VM kiosk client '${client}' needs an identity.ssh.hostKeys entry.";
    })
    vm.kioskClients;

  systemd.tmpfiles.rules = [
    "d ${vmStateDir} 0750 qemu-libvirtd qemu-libvirtd -"
  ];

  # Reconcile the persistent libvirt definition on boot and whenever its Nix
  # definition changes. Starting and stopping the guest remains explicit.
  systemd.services."libvirt-domain-${vmName}" = {
    description = "Define the ${vmName} libvirt domain";
    wantedBy = ["multi-user.target"];
    requires = ["libvirtd.service"];
    after = ["libvirtd.service" "systemd-tmpfiles-setup.service"];
    restartTriggers = [domainXml];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = defineDomain;
    };
  };
}
