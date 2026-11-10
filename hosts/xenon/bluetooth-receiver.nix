# NixOS support for AuxQ's Bluetooth audio receiver and BLE device link.
#
# PipeWire registers the system-wide A2DP sink used for phone audio, while
# BlueZ provides AVRCP. auxq-slint registers its own BLE GATT service and
# advertisement through blew; no separate BLE daemon is needed here.
{...}: {
  hardware.bluetooth = {
    enable = true;
    powerOnBoot = true;

    settings = {
      General = {
        # These plugins probe encrypted Apple characteristics during BLE
        # discovery, which can cause unwanted pairing prompts.
        DisablePlugins = "battery,deviceinfo";
      };

      GATT = {
        # Prevent service discovery from reading and caching encrypted
        # characteristics on Apple devices. This is required by blew.
        Cache = "no";
      };

      Policy = {
        AutoEnable = true;
      };
    };
  };

  security.rtkit.enable = true;

  services.pipewire = {
    enable = true;
    audio.enable = true;
    pulse.enable = true;

    wireplumber = {
      enable = true;
      extraConfig."10-auxq-bluetooth" = {
        "monitor.bluez.properties" = {
          # a2dp_sink makes this machine an audio output for a phone. Keep the
          # other roles so importing this on a desktop does not disable normal
          # Bluetooth headphones and headset profiles.
          "bluez5.roles" = [
            "a2dp_sink"
            "a2dp_source"
            "bap_sink"
            "bap_source"
            "hsp_hs"
            "hsp_ag"
            "hfp_hf"
            "hfp_ag"
          ];
        };
      };
    };
  };
}
