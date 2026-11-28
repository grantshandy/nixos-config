# Battery and external-power telemetry for portable fleet hosts.
{
  config,
  lib,
  ...
}: let
  batteryTag = "battery";
  batteryHosts =
    config.fleet.hosts
    |> lib.filterAttrs (_: host: lib.elem batteryTag host.tags)
    |> lib.attrNames;
  textfileDir = config.fleet.monitoring.textfileDir;
in {
  fleet.aspects.battery-monitoring.tags = [batteryTag];

  fleet.monitoring.scrapeJobs.laptop-power = {
    hosts = batteryHosts;
    interval = "15s";
    collectors = ["textfile"];
    keepMetrics = ["laptop_.*"];
  };

  flake.modules.nixos.battery-monitoring = {pkgs, ...}: let
    collectPower = pkgs.writeShellApplication {
      name = "collect-laptop-power";
      runtimeInputs = [pkgs.coreutils];
      text = ''
        output=${textfileDir}/laptop-power.prom
        temporary="$(mktemp --tmpdir=${textfileDir} .laptop-power.prom.XXXXXX)"
        trap 'rm -f "$temporary"' EXIT

        battery_count=0
        capacity_sum=0
        external_power_count=0
        external_power_connected=0

        {
          printf '%s\n' \
            '# HELP laptop_battery_device_charge_percent Current charge percentage of one battery.' \
            '# TYPE laptop_battery_device_charge_percent gauge' \
            '# HELP laptop_external_power_device_connected Whether one external power supply is online (1=yes, 0=no).' \
            '# TYPE laptop_external_power_device_connected gauge'

          for supply in /sys/class/power_supply/*; do
            [[ -d "$supply" && -r "$supply/type" ]] || continue
            device="''${supply##*/}"
            type="$(cat "$supply/type")"

            if [[ "$type" == Battery ]]; then
              [[ -r "$supply/capacity" ]] || continue
              capacity="$(cat "$supply/capacity")"
              printf 'laptop_battery_device_charge_percent{device="%s"} %s\n' "$device" "$capacity"
              battery_count=$((battery_count + 1))
              capacity_sum=$((capacity_sum + capacity))
            elif [[ -r "$supply/online" ]]; then
              online="$(cat "$supply/online")"
              printf 'laptop_external_power_device_connected{device="%s",type="%s"} %s\n' \
                "$device" "$type" "$online"
              external_power_count=$((external_power_count + 1))
              if [[ "$online" == 1 ]]; then
                external_power_connected=1
              fi
            fi
          done

          if ((battery_count == 0)); then
            rm -f "$output"
            echo "No battery power supplies expose a capacity metric" >&2
            exit 1
          fi

          printf '%s\n' \
            '# HELP laptop_battery_charge_percent Mean charge percentage across all detected batteries.' \
            '# TYPE laptop_battery_charge_percent gauge' \
            "laptop_battery_charge_percent $((capacity_sum / battery_count))" \
            '# HELP laptop_ac_power_connected Whether any detected external power supply is online (1=yes, 0=no).' \
            '# TYPE laptop_ac_power_connected gauge' \
            "laptop_ac_power_connected $external_power_connected" \
            '# HELP laptop_external_power_device_count Number of detected external power supplies exposing online state.' \
            '# TYPE laptop_external_power_device_count gauge' \
            "laptop_external_power_device_count $external_power_count"
        } > "$temporary"

        chmod 0644 "$temporary"
        mv --force "$temporary" "$output"
        trap - EXIT
      '';
    };
  in {
    systemd.services.collect-laptop-power = {
      description = "Export laptop battery and external-power metrics";
      serviceConfig = {
        Type = "oneshot";
        ExecStart = lib.getExe collectPower;
        PrivateTmp = true;
        ProtectHome = true;
        ProtectSystem = "strict";
        ReadWritePaths = [textfileDir];
      };
    };

    systemd.timers.collect-laptop-power = {
      description = "Periodically sample laptop battery and external power";
      wantedBy = ["timers.target"];
      timerConfig = {
        OnBootSec = "30s";
        OnUnitActiveSec = "30s";
        AccuracySec = "5s";
        Persistent = true;
      };
    };
  };

  fleet.monitoring.dashboards.laptop-power = let
    perses = import ./_lib.nix {inherit lib;};
    inherit (perses) query timeSeries stat thresholds colors mapValue group labelVariable;
    selector = "job=\"laptop-power\",host=~\"$host\"";
    legend = {
      position = "bottom";
      mode = "table";
      values = ["mean" "min" "max" "last"];
    };
  in {
    title = "Laptop Power";
    duration = "24h";
    refreshInterval = "30s";

    variables = [
      (labelVariable {
        name = "host";
        title = "Laptop";
        matchers = ["laptop_battery_charge_percent{job=\"laptop-power\"}"];
        multiple = true;
        all = true;
        allValue = ".*";
        default = ["$__all"];
      })
    ];

    panels = {
      ac_status = stat {
        name = "External power";
        description = "Whether the selected laptop is currently connected to external power.";
        queries = [
          (query {
            expr = "laptop_ac_power_connected{${selector}}";
            legend = "{{host}}";
          })
        ];
        colorMode = "background_solid";
        mappings = [
          (mapValue 0 "Disconnected" colors.orange)
          (mapValue 1 "Connected" colors.green)
        ];
      };

      battery_history = timeSeries {
        name = "Battery charge";
        description = "Battery charge percentage over time.";
        queries = [
          (query {
            expr = "laptop_battery_charge_percent{${selector}}";
            legend = "{{host}}";
          })
        ];
        unit = "percent";
        decimals = 0;
        min = 0;
        max = 100;
        inherit legend;
        thresholds = thresholds [
          {
            value = 0;
            color = colors.red;
          }
          {
            value = 20;
            color = colors.orange;
          }
          {
            value = 50;
            color = colors.green;
          }
        ];
      };

      ac_history = timeSeries {
        name = "External power history";
        description = "One means external power was connected; zero means the laptop was on battery.";
        queries = [
          (query {
            expr = "laptop_ac_power_connected{${selector}}";
            legend = "{{host}}";
          })
        ];
        unit = "decimal";
        decimals = 0;
        min = 0;
        max = 1;
        label = "Connected";
        inherit legend;
      };
    };

    layouts = [
      (group {
        title = "Power";
        items = [
          {
            panel = "ac_status";
            width = 6;
            height = 5;
          }
          {
            panel = "battery_history";
            width = 18;
            height = 10;
          }
          {
            panel = "ac_history";
            width = 24;
            height = 8;
          }
        ];
      })
    ];
  };
}
