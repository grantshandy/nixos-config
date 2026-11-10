# NixOS module for a short-range presentation hotspot.
#
# Porting to another machine:
#   1. Set wifiInterface below to its physical Wi-Fi interface (`iw dev`).
#   2. Check `iw list` for AP support and the "valid interface combinations" section.
#   3. Leave concurrent = true when managed + AP is supported on one channel.
#      Otherwise set it to false; starting the hotspot will then replace the normal
#      Wi-Fi connection instead of sharing the radio.
#   4. Import this module, rebuild, and reboot if the virtual interface is new.
#
# Usage:
#   presentation-hotspot up
#   presentation-hotspot down
#   presentation-hotspot status
#
# In concurrent mode the command detects the upstream Wi-Fi channel at runtime and
# puts the AP on that channel. NetworkManager supplies DHCP, DNS, forwarding, and NAT.
{
  lib,
  pkgs,
  ...
}: let
  wifiInterface = "wlo1"; # The only machine-specific setting in the common case.
  concurrent = true;

  hotspotInterface = "auxq-hotspot";
  hotspotDevice = if concurrent then hotspotInterface else wifiInterface;
  hotspotSsid = "AuxQ-Presentation";
  hotspotAddress = "10.42.0.1/24";

  presentationHotspot = pkgs.writeShellApplication {
    name = "presentation-hotspot";
    runtimeInputs = [
      pkgs.gawk
      pkgs.iw
      pkgs.networkmanager
    ];
    text = ''
      action="''${1:-status}"

      case "$action" in
        up)
          ${lib.optionalString concurrent ''
            upstream_connection="$(${pkgs.networkmanager}/bin/nmcli -g GENERAL.CONNECTION device show ${wifiInterface})"

            # On a fresh installation an unrestricted saved profile can briefly attach
            # to the new virtual interface. Move it to the physical interface first.
            if [[ -z "$upstream_connection" || "$upstream_connection" == "--" ]]; then
              misplaced_connection="$(${pkgs.networkmanager}/bin/nmcli -g GENERAL.CONNECTION device show ${hotspotInterface})"
              if [[ -n "$misplaced_connection" && "$misplaced_connection" != "--" && "$misplaced_connection" != "${hotspotSsid}" ]]; then
                ${pkgs.networkmanager}/bin/nmcli connection down "$misplaced_connection"
                ${pkgs.networkmanager}/bin/nmcli connection modify "$misplaced_connection" connection.interface-name ${wifiInterface}
                ${pkgs.networkmanager}/bin/nmcli connection up "$misplaced_connection" ifname ${wifiInterface}
                upstream_connection="$misplaced_connection"
              fi
            fi

            if [[ -z "$upstream_connection" || "$upstream_connection" == "--" ]]; then
              echo "${wifiInterface} must be connected before starting the concurrent hotspot" >&2
              exit 1
            fi

            # Prevent the upstream profile from attaching to the virtual AP interface
            # on later boots. Do not pin a BSSID, so it can still roam normally.
            ${pkgs.networkmanager}/bin/nmcli connection modify "$upstream_connection" connection.interface-name ${wifiInterface}

            channel="$(${pkgs.iw}/bin/iw dev ${wifiInterface} info | ${pkgs.gawk}/bin/awk '$1 == "channel" { print $2; exit }')"
            if [[ -z "$channel" ]]; then
              echo "Could not determine the channel used by ${wifiInterface}" >&2
              exit 1
            fi

            if (( channel <= 14 )); then
              band="bg"
            else
              band="a"
            fi

            ${pkgs.networkmanager}/bin/nmcli connection modify ${lib.escapeShellArg hotspotSsid} \
              802-11-wireless.band "$band" \
              802-11-wireless.channel "$channel"
          ''}
          ${pkgs.networkmanager}/bin/nmcli connection up ${lib.escapeShellArg hotspotSsid}
          ;;
        down)
          ${pkgs.networkmanager}/bin/nmcli connection down ${lib.escapeShellArg hotspotSsid}
          ;;
        status)
          ${pkgs.networkmanager}/bin/nmcli device status
          ${pkgs.iw}/bin/iw dev
          ;;
        *)
          echo "Usage: presentation-hotspot {up|down|status}" >&2
          exit 2
          ;;
      esac
    '';
  };
in {
  environment.systemPackages = [
    pkgs.iw
    presentationHotspot
  ];

  # A concurrent AP needs a second interface on the physical Wi-Fi radio.
  networking.wlanInterfaces = lib.mkIf concurrent {
    ${wifiInterface}.device = wifiInterface;
    ${hotspotInterface} = {
      device = wifiInterface;
      mac = "02:00:00:00:42:01";
    };
  };

  # Permit clients to obtain an address and use NetworkManager's local DNS proxy.
  networking.firewall.interfaces.${hotspotDevice} = {
    allowedUDPPorts = [53 67 4533];
    allowedTCPPorts = [53 4533];
  };

  networking.networkmanager = {
    enable = true;

    ensureProfiles.profiles.${hotspotSsid} = {
      connection = {
        id = hotspotSsid;
        type = "wifi";
        interface-name = hotspotDevice;
        autoconnect = false;
      };

      wifi =
        {
          mode = "ap";
          ssid = hotspotSsid;
          powersave = 2; # NM_SETTING_WIRELESS_POWERSAVE_DISABLE.
        }
        // lib.optionalAttrs (!concurrent) {
          # Conservative fallback for cards that cannot run managed + AP together.
          band = "bg";
          channel = 6;
        };

      wifi-security = {
        key-mgmt = "wpa-psk";
        proto = "rsn"; # WPA2 rather than legacy WPA.
        pairwise = "ccmp";
        group = "ccmp";
        psk = "password";
      };

      ipv4 = {
        method = "shared";
        address1 = hotspotAddress;
      };

      ipv6.method = "disabled";
    };
  };
}

# Once the phone is connected, open Developer options -> Wireless debugging.
#
#   adb pair 10.42.0.PHONE:PAIRING_PORT
#   adb connect 10.42.0.PHONE:DEBUG_PORT
#   scrcpy --no-audio --video-bit-rate=8M --max-fps=60
#
# `--no-audio` leaves playback on the phone/headphones. Use `--audio-dup` instead
# when audio should play on both Android and the laptop.
