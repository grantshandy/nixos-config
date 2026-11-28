# The fleet overview dashboard: one panel per thing worth knowing about every
# machine at once, plus a per-host section that Perses repeats for each host the
# `host` variable selects.
#
# Host names appear nowhere below. The fleet-wide panels group by the `host`
# label that `perses.nix` attaches to each scrape target, and the per-host
# section is driven by a variable whose options are the values of that same
# label, so adding a machine to the registry adds it to this dashboard.
#
# Several panels are lifted from Perses' own node-exporter-full demo dashboard
# (`nodeexporterfull.json`): the gauge row, the stacked CPU and memory
# breakdowns, the mirrored read/write pairs via `negativeY`, and legends that
# carry mean/max/last columns.
{lib, ...}: let
  perses = import ./_lib.nix {inherit lib;};
  inherit (perses) query timeSeries gauge stat thresholds colors mapValue group labelVariable;

  # Shared by every fleet-wide panel, so panels never pick up the textfile-only
  # `ci-jobs`/`llm-metrics` jobs that scrape the same exporters.
  nodes = "job=\"nodes\"";

  # Mean/max/last under each series, which is what makes a chart with one line
  # per host readable without hovering.
  tableLegend = {
    position = "bottom";
    mode = "table";
    values = ["mean" "max" "last"];
  };

  usageThresholds = thresholds [
    {
      value = 0;
      color = colors.green;
    }
    {
      value = 70;
      color = colors.orange;
    }
    {
      value = 90;
      color = colors.red;
    }
  ];

  temperatureThresholds = thresholds [
    {
      value = 0;
      color = colors.green;
    }
    {
      value = 70;
      color = colors.orange;
    }
    {
      value = 85;
      color = colors.red;
    }
  ];

  # Percent-of-CPU-time busy, per host. The same shape is reused for a gauge
  # (instantaneous) and a time series (history).
  cpuBusy = selector: "100 - (avg by (host) (rate(node_cpu_seconds_total{${selector},mode=\"idle\"}[$__rate_interval])) * 100)";
  memoryUsed = selector: "100 * (1 - node_memory_MemAvailable_bytes{${selector}} / node_memory_MemTotal_bytes{${selector}})";
  rootFilesystemUsed = selector: "100 * (1 - node_filesystem_avail_bytes{${selector},mountpoint=\"/\"} / node_filesystem_size_bytes{${selector},mountpoint=\"/\"})";
  # The chip filter keeps this to CPU package/core sensors; the same exporters
  # also report drive, chipset and GPU temperatures.
  cpuTemperature = selector: "max by (host) (node_hwmon_temp_celsius{${selector},chip=~\"platform_coretemp_0|pci0000:00_0000:00:18_3\"})";

  # Per-host section: `$host` is substituted with one value at a time, because
  # Perses renders this whole section once per selected host.
  host = "${nodes},host=\"$host\"";

  # A CPU-time breakdown that stacks to 100%, as in the demo dashboard's "CPU
  # Basic" panel.
  cpuMode = mode: label:
    query {
      expr = "100 * sum by (host) (rate(node_cpu_seconds_total{${host},mode=~\"${mode}\"}[$__rate_interval])) / on (host) sum by (host) (rate(node_cpu_seconds_total{${host}}[$__rate_interval]))";
      legend = label;
    };

  stacked = {
    display = "line";
    areaOpacity = 0.6;
    lineWidth = 0.5;
    stack = "all";
    connectNulls = true;
  };

  # Pairs a "positive" and a "negative" query so one is drawn mirrored below the
  # axis, which reads far better than two overlapping lines.
  mirrored = [
    {queryIndex = 0;}
    {
      queryIndex = 1;
      negativeY = true;
    }
  ];
in {
  fleet.monitoring.dashboards.fleet-overview = {
    title = "Fleet Overview";

    variables = [
      (labelVariable {
        name = "host";
        title = "Host";
        matchers = ["up{${nodes}}"];
        multiple = true;
        all = true;
        default = ["$__all"];
        description = "Hosts the per-host section at the bottom is repeated for.";
      })
    ];

    panels = {
      online = stat {
        name = "Online";
        queries = [
          (query {
            expr = "up{${nodes}}";
            legend = "{{host}}";
          })
        ];
        colorMode = "background_solid";
        mappings = [
          (mapValue 0 "Offline" colors.red)
          (mapValue 1 "Online" colors.green)
        ];
      };

      cpu_busy = gauge {
        name = "CPU busy";
        description = "Share of CPU time not spent idle, right now.";
        queries = [
          (query {
            expr = cpuBusy nodes;
            legend = "{{host}}";
          })
        ];
        unit = "percent";
        decimals = 0;
        max = 100;
        thresholds = usageThresholds;
      };

      memory_used = gauge {
        name = "Memory used";
        queries = [
          (query {
            expr = memoryUsed nodes;
            legend = "{{host}}";
          })
        ];
        unit = "percent";
        decimals = 0;
        max = 100;
        thresholds = usageThresholds;
      };

      root_filesystem_used = gauge {
        name = "Root filesystem used";
        queries = [
          (query {
            expr = rootFilesystemUsed nodes;
            legend = "{{host}}";
          })
        ];
        unit = "percent";
        decimals = 0;
        max = 100;
        thresholds = usageThresholds;
      };

      cpu_temperature_now = gauge {
        name = "CPU temperature";
        description = "Hottest reported CPU package/core sensor per host; non-CPU thermal sensors are excluded.";
        queries = [
          (query {
            expr = cpuTemperature nodes;
            legend = "{{host}}";
          })
        ];
        unit = "celsius";
        decimals = 0;
        max = 100;
        thresholds = temperatureThresholds;
      };

      uptime = stat {
        name = "Uptime";
        queries = [
          (query {
            expr = "node_time_seconds{${nodes}} - node_boot_time_seconds{${nodes}}";
            legend = "{{host}}";
          })
        ];
        unit = "seconds";
        decimals = 0;
      };

      cpu_usage = timeSeries {
        name = "CPU usage";
        queries = [
          (query {
            expr = cpuBusy nodes;
            legend = "{{host}}";
          })
        ];
        unit = "percent";
        decimals = 0;
        min = 0;
        max = 100;
        legend = tableLegend;
      };

      load_average = timeSeries {
        name = "Load average (1m)";
        description = "Runnable plus uninterruptible tasks, averaged over a minute. Compare against each host's core count rather than against the other hosts.";
        queries = [
          (query {
            expr = "node_load1{${nodes}}";
            legend = "{{host}}";
          })
        ];
        unit = "decimal";
        min = 0;
        legend = tableLegend;
      };

      memory_usage = timeSeries {
        name = "Memory usage";
        queries = [
          (query {
            expr = memoryUsed nodes;
            legend = "{{host}}";
          })
        ];
        unit = "percent";
        decimals = 0;
        min = 0;
        max = 100;
        legend = tableLegend;
      };

      cpu_temperature = timeSeries {
        name = "CPU temperature";
        description = "Hottest reported CPU package/core sensor per host; non-CPU thermal sensors are excluded.";
        queries = [
          (query {
            expr = cpuTemperature nodes;
            legend = "{{host}}";
          })
        ];
        unit = "celsius";
        min = 0;
        thresholds = temperatureThresholds;
        legend = tableLegend;
      };

      network_traffic = timeSeries {
        name = "Network traffic";
        description = "Received above the axis, sent mirrored below it. Excludes tailscale0, which the panel below counts instead.";
        queries = [
          (query {
            expr = "sum by (host) (rate(node_network_receive_bytes_total{${nodes},device!~\"lo|tailscale0\"}[$__rate_interval]))";
            legend = "{{host}} rx";
          })
          (query {
            expr = "sum by (host) (rate(node_network_transmit_bytes_total{${nodes},device!~\"lo|tailscale0\"}[$__rate_interval]))";
            legend = "{{host}} tx";
          })
        ];
        unit = "bytes/sec";
        querySettings = mirrored;
        legend = tableLegend;
      };

      tailnet_throughput = timeSeries {
        name = "Aggregate tailnet throughput";
        description = "Sum of tailscale0 transmit rates. Counting only the sending side avoids double-counting traffic received by another monitored host.";
        queries = [
          (query {
            expr = "sum(rate(node_network_transmit_bytes_total{${nodes},device=\"tailscale0\"}[$__rate_interval]))";
            legend = "tailnet throughput";
          })
        ];
        unit = "bytes/sec";
        min = 0;
      };

      network_errors = timeSeries {
        name = "Network errors and drops";
        description = "Interface-level errors and dropped packets. Flat at zero is the expected reading.";
        queries = [
          (query {
            expr = "sum by (host) (rate(node_network_receive_errs_total{${nodes},device!=\"lo\"}[$__rate_interval]) + rate(node_network_receive_drop_total{${nodes},device!=\"lo\"}[$__rate_interval]))";
            legend = "{{host}} rx";
          })
          (query {
            expr = "sum by (host) (rate(node_network_transmit_errs_total{${nodes},device!=\"lo\"}[$__rate_interval]) + rate(node_network_transmit_drop_total{${nodes},device!=\"lo\"}[$__rate_interval]))";
            legend = "{{host}} tx";
          })
        ];
        unit = "packets/sec";
        min = 0;
        legend = tableLegend;
      };

      filesystem_usage = timeSeries {
        name = "Filesystem usage";
        description = "Real filesystems only; tmpfs and container overlays are excluded.";
        queries = [
          (query {
            expr = "100 * (1 - node_filesystem_avail_bytes{${nodes},mountpoint=~\"/|/mnt/media|/mnt/extra-usb\",fstype!~\"tmpfs|overlay\"} / node_filesystem_size_bytes{${nodes},mountpoint=~\"/|/mnt/media|/mnt/extra-usb\",fstype!~\"tmpfs|overlay\"})";
            legend = "{{host}}: {{mountpoint}}";
          })
        ];
        unit = "percent";
        decimals = 0;
        min = 0;
        max = 100;
        thresholds = usageThresholds;
        visual.connectNulls = true;
        legend = tableLegend;
      };

      disk_throughput = timeSeries {
        name = "Disk throughput";
        description = "Reads above the axis, writes mirrored below it.";
        queries = [
          (query {
            expr = "sum by (host) (rate(node_disk_read_bytes_total{${nodes}}[$__rate_interval]))";
            legend = "{{host}} read";
          })
          (query {
            expr = "sum by (host) (rate(node_disk_written_bytes_total{${nodes}}[$__rate_interval]))";
            legend = "{{host}} write";
          })
        ];
        unit = "bytes/sec";
        querySettings = mirrored;
        legend = tableLegend;
      };

      disk_busy = timeSeries {
        name = "Disk busy";
        description = "Share of wall-clock time the busiest block device on each host spent servicing I/O.";
        queries = [
          (query {
            expr = "100 * max by (host) (rate(node_disk_io_time_seconds_total{${nodes}}[$__rate_interval]))";
            legend = "{{host}}";
          })
        ];
        unit = "percent";
        decimals = 0;
        min = 0;
        legend = tableLegend;
      };

      nix_store_size = timeSeries {
        name = "Nix store size";
        description = "Measured by the textfile collector's half-hourly `du`, so it steps rather than curves.";
        queries = [
          (query {
            expr = "nix_store_disk_bytes";
            legend = "{{host}}";
          })
        ];
        unit = "bytes";
        visual.connectNulls = true;
        legend = tableLegend;
      };

      failed_units = stat {
        name = "Failed units";
        description = "systemd units in the failed state. Anything but zero wants looking at.";
        queries = [
          (query {
            expr = "sum by (host) (node_systemd_unit_state{${nodes},state=\"failed\"})";
            legend = "{{host}}";
          })
        ];
        unit = "decimal";
        decimals = 0;
        colorMode = "background_solid";
        mappings = [(mapValue 0 "0" colors.green)];
        thresholds = thresholds [
          {
            value = 0;
            color = colors.green;
          }
          {
            value = 1;
            color = colors.red;
          }
        ];
      };

      processes = timeSeries {
        name = "Processes";
        description = "Runnable above the axis, blocked on I/O mirrored below it.";
        queries = [
          (query {
            expr = "node_procs_running{${nodes}}";
            legend = "{{host}} running";
          })
          (query {
            expr = "node_procs_blocked{${nodes}}";
            legend = "{{host}} blocked";
          })
        ];
        unit = "decimal";
        querySettings = mirrored;
        legend = tableLegend;
      };

      file_descriptors = timeSeries {
        name = "File descriptors used";
        queries = [
          (query {
            expr = "100 * node_filefd_allocated{${nodes}} / node_filefd_maximum{${nodes}}";
            legend = "{{host}}";
          })
        ];
        unit = "percent";
        decimals = 1;
        min = 0;
        legend = tableLegend;
      };

      context_switches = timeSeries {
        name = "Context switches and interrupts";
        queries = [
          (query {
            expr = "rate(node_context_switches_total{${nodes}}[$__rate_interval])";
            legend = "{{host}} context switches";
          })
          (query {
            expr = "rate(node_intr_total{${nodes}}[$__rate_interval])";
            legend = "{{host}} interrupts";
          })
        ];
        unit = "ops/sec";
        min = 0;
        legend = tableLegend;
      };

      host_cpu_modes = timeSeries {
        name = "CPU by mode";
        description = "Stacks to the share of total CPU time, so the gap below 100% is idle.";
        queries = [
          (cpuMode "system" "system")
          (cpuMode "user" "user")
          (cpuMode "iowait" "iowait")
          (cpuMode ".*irq" "irq")
          (cpuMode "steal|nice|guest.*" "other")
        ];
        unit = "percent";
        decimals = 0;
        min = 0;
        max = 100;
        visual = stacked;
      };

      host_memory = timeSeries {
        name = "Memory breakdown";
        description = "Stacks to total RAM: what applications hold, what the kernel can reclaim, and what is free.";
        queries = [
          (query {
            expr = "node_memory_MemTotal_bytes{${host}} - node_memory_MemFree_bytes{${host}} - node_memory_Buffers_bytes{${host}} - node_memory_Cached_bytes{${host}} - node_memory_SReclaimable_bytes{${host}}";
            legend = "used";
          })
          (query {
            expr = "node_memory_Buffers_bytes{${host}} + node_memory_Cached_bytes{${host}} + node_memory_SReclaimable_bytes{${host}}";
            legend = "cache and buffers";
          })
          (query {
            expr = "node_memory_MemFree_bytes{${host}}";
            legend = "free";
          })
        ];
        unit = "bytes";
        min = 0;
        visual = stacked;
      };

      host_load = timeSeries {
        name = "Load average";
        description = "Divided by core count, so 100% means the machine is exactly saturated.";
        queries = [
          (query {
            expr = "100 * node_load1{${host}} / count(count by (cpu) (node_cpu_seconds_total{${host}}))";
            legend = "1m";
          })
          (query {
            expr = "100 * node_load5{${host}} / count(count by (cpu) (node_cpu_seconds_total{${host}}))";
            legend = "5m";
          })
          (query {
            expr = "100 * node_load15{${host}} / count(count by (cpu) (node_cpu_seconds_total{${host}}))";
            legend = "15m";
          })
        ];
        unit = "percent";
        decimals = 0;
        min = 0;
        thresholds = thresholds [
          {
            value = 0;
            color = colors.green;
          }
          {
            value = 100;
            color = colors.orange;
          }
        ];
      };

      host_disk_io = timeSeries {
        name = "Disk I/O by device";
        description = "Reads above the axis, writes mirrored below it.";
        queries = [
          (query {
            expr = "rate(node_disk_read_bytes_total{${host}}[$__rate_interval])";
            legend = "{{device}} read";
          })
          (query {
            expr = "rate(node_disk_written_bytes_total{${host}}[$__rate_interval])";
            legend = "{{device}} write";
          })
        ];
        unit = "bytes/sec";
        querySettings = mirrored;
      };

      host_network = timeSeries {
        name = "Network by interface";
        description = "Received above the axis, sent mirrored below it.";
        queries = [
          (query {
            expr = "rate(node_network_receive_bytes_total{${host},device!=\"lo\"}[$__rate_interval])";
            legend = "{{device}} rx";
          })
          (query {
            expr = "rate(node_network_transmit_bytes_total{${host},device!=\"lo\"}[$__rate_interval])";
            legend = "{{device}} tx";
          })
        ];
        unit = "bytes/sec";
        querySettings = mirrored;
      };

      host_filesystems = timeSeries {
        name = "Filesystem free space";
        queries = [
          (query {
            expr = "node_filesystem_avail_bytes{${host},fstype!~\"tmpfs|overlay\"}";
            legend = "{{mountpoint}}";
          })
        ];
        unit = "bytes";
        min = 0;
        visual.connectNulls = true;
      };
    };

    layouts = [
      (group {
        title = "At a glance";
        items = [
          {
            panel = "online";
            width = 8;
            height = 5;
          }
          {
            panel = "uptime";
            width = 8;
            height = 5;
          }
          {
            panel = "failed_units";
            width = 8;
            height = 5;
          }
          {
            panel = "cpu_busy";
            width = 6;
            height = 6;
          }
          {
            panel = "memory_used";
            width = 6;
            height = 6;
          }
          {
            panel = "root_filesystem_used";
            width = 6;
            height = 6;
          }
          {
            panel = "cpu_temperature_now";
            width = 6;
            height = 6;
          }
        ];
      })

      (group {
        title = "Compute";
        items = [
          {
            panel = "cpu_usage";
            width = 12;
            height = 9;
          }
          {
            panel = "memory_usage";
            width = 12;
            height = 9;
          }
          {
            panel = "load_average";
            width = 12;
            height = 9;
          }
          {
            panel = "cpu_temperature";
            width = 12;
            height = 9;
          }
        ];
      })

      (group {
        title = "Network";
        items = [
          {
            panel = "network_traffic";
            width = 12;
            height = 10;
          }
          {
            panel = "tailnet_throughput";
            width = 12;
            height = 10;
          }
          {
            panel = "network_errors";
            width = 24;
            height = 9;
          }
        ];
      })

      (group {
        title = "Storage";
        items = [
          {
            panel = "filesystem_usage";
            width = 12;
            height = 10;
          }
          {
            panel = "nix_store_size";
            width = 12;
            height = 10;
          }
          {
            panel = "disk_throughput";
            width = 12;
            height = 9;
          }
          {
            panel = "disk_busy";
            width = 12;
            height = 9;
          }
        ];
      })

      (group {
        title = "Operating system";
        open = false;
        items = [
          {
            panel = "processes";
            width = 8;
            height = 9;
          }
          {
            panel = "file_descriptors";
            width = 8;
            height = 9;
          }
          {
            panel = "context_switches";
            width = 8;
            height = 9;
          }
        ];
      })

      (group {
        title = "$host";
        open = false;
        repeat = "host";
        items = [
          {
            panel = "host_cpu_modes";
            width = 12;
            height = 9;
          }
          {
            panel = "host_memory";
            width = 12;
            height = 9;
          }
          {
            panel = "host_load";
            width = 8;
            height = 8;
          }
          {
            panel = "host_disk_io";
            width = 8;
            height = 8;
          }
          {
            panel = "host_network";
            width = 8;
            height = 8;
          }
          {
            panel = "host_filesystems";
            width = 24;
            height = 8;
          }
        ];
      })
    ];
  };
}
