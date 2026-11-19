{
  config,
  lib,
  pkgs,
  ...
}: let
  rdpPort = 3389;
  stateDir = "/var/lib/gnome-remote-desktop";
  tlsCertificate = "${stateDir}/rdp-tls.crt";
  tlsKey = "${stateDir}/rdp-tls.key";
  credentialsDir = "${stateDir}/.local/share/gnome-remote-desktop";
  credentialsFile = "${credentialsDir}/credentials.ini";
  remoteHostName = "xenon.ts.${config.identity.homelab.dns}";
  grdctl = lib.getExe' pkgs.gnome-remote-desktop "grdctl";
in {
  services.gnome.gnome-remote-desktop.enable = true;

  age.secrets.gnome-remote-desktop-credentials = {
    file = ../../secrets/gnome-remote-desktop-credentials.age;
    mode = "0400";
  };

  # RDP is reachable only through Tailscale, never Xenon's LAN interfaces.
  networking.firewall.interfaces.tailscale0.allowedTCPPorts = [rdpPort];

  systemd.services.gnome-remote-desktop-setup = {
    description = "Configure GNOME system remote login";
    wantedBy = ["graphical.target"];
    requiredBy = ["gnome-remote-desktop.service"];
    before = ["gnome-remote-desktop.service"];
    path = [pkgs.polkit];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      set -a
      source ${config.age.secrets.gnome-remote-desktop-credentials.path}
      set +a

      ${lib.getExe' pkgs.coreutils "install"} \
        --directory \
        --mode=0700 \
        --owner=gnome-remote-desktop \
        --group=gnome-remote-desktop \
        ${stateDir}

      if [[ ! -s ${tlsCertificate} || ! -s ${tlsKey} ]]; then
        ${lib.getExe pkgs.openssl} req \
          -x509 \
          -newkey rsa:3072 \
          -sha256 \
          -nodes \
          -days 3650 \
          -subj /CN=${remoteHostName} \
          -addext subjectAltName=DNS:${remoteHostName},DNS:xenon \
          -keyout ${tlsKey} \
          -out ${tlsCertificate}
      fi

      ${lib.getExe' pkgs.coreutils "chown"} \
        gnome-remote-desktop:gnome-remote-desktop \
        ${tlsCertificate} \
        ${tlsKey}
      ${lib.getExe' pkgs.coreutils "chmod"} 0444 ${tlsCertificate}
      ${lib.getExe' pkgs.coreutils "chmod"} 0400 ${tlsKey}

      ${lib.getExe' pkgs.coreutils "install"} \
        --directory \
        --mode=0700 \
        --owner=gnome-remote-desktop \
        --group=gnome-remote-desktop \
        ${credentialsDir}

      credentials_tmp="$(${lib.getExe' pkgs.coreutils "mktemp"})"
      trap '${lib.getExe' pkgs.coreutils "rm"} -f "$credentials_tmp"' EXIT
      printf "[RDP]\ncredentials={'username': <'%s'>, 'password': <'%s'>}\n" \
        "$RDP_USERNAME" \
        "$RDP_PASSWORD" \
        >"$credentials_tmp"
      ${lib.getExe' pkgs.coreutils "install"} \
        --mode=0600 \
        --owner=gnome-remote-desktop \
        --group=gnome-remote-desktop \
        "$credentials_tmp" \
        ${credentialsFile}

      ${grdctl} --system rdp set-port ${toString rdpPort}
      ${grdctl} --system rdp set-auth-methods credentials
      ${grdctl} --system rdp set-tls-cert ${tlsCertificate}
      ${grdctl} --system rdp set-tls-key ${tlsKey}
      ${grdctl} --system rdp disable-view-only
      ${grdctl} --system rdp disable-port-negotiation
      ${grdctl} --system rdp enable
    '';
  };

  systemd.services.gnome-remote-desktop = {
    wantedBy = ["graphical.target"];
    after = ["gnome-remote-desktop-setup.service" "tailscaled.service"];
    wants = ["tailscaled.service"];
    restartTriggers = [config.age.secrets.gnome-remote-desktop-credentials.file];
  };
}
