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
  vmStateDir = "/var/lib/libvirt/images/${vmName}";
  vmDisk = "${vmStateDir}/system.qcow2";

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
        <controller type="ide" index="0"/>
        <controller type="usb" index="0" model="piix3-uhci"/>

        <!-- User-mode networking keeps unsupported Windows XP off the LAN. -->
        <interface type="user">
          <model type="rtl8139"/>
        </interface>

        <input type="mouse" bus="ps2"/>
        <input type="keyboard" bus="ps2"/>
        <input type="tablet" bus="usb"/>

        <graphics type="spice" autoport="yes">
          <listen type="address" address="127.0.0.1"/>
          <image compression="auto_glz"/>
          <jpeg compression="auto"/>
          <zlib compression="auto"/>
          <playback compression="on"/>
          <streaming mode="filter"/>
          <gl enable="no"/>
        </graphics>
        <video>
          <model type="vga" vram="16384" heads="1" primary="yes"/>
        </video>
        <audio id="1" type="spice"/>
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

  users.users.${config.identity.user.name}.extraGroups = ["libvirtd"];
  users.users.${kioskUser} = {
    isSystemUser = true;
    group = kioskUser;
    extraGroups = ["libvirtd"];
    shell = pkgs.bashInteractive;
    openssh.authorizedKeys.keys =
      map (
        client: "restrict ${config.identity.ssh.hostKeys.${client}}"
      )
      kioskClientsWithHostKeys;
  };
  users.groups.${kioskUser} = {};

  assertions =
    map (client: {
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
