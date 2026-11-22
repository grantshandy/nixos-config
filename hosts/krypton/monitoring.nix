{
  config,
  lib,
  pkgs,
  ...
}: let
  dns = config.identity.homelab.dns;
  grafanaPort = 3000;
  victoriaMetricsPort = 8428;
  grafanaService = config.network.hosts.krypton.publicWebServices.Grafana;
  grafanaHost = "${grafanaService.subdomain}.${dns}";
  monitoredHosts =
    config.network.hosts
    |> lib.filterAttrs (_: host: host.tailscale.enable)
    |> lib.attrNames;

  scrapeTargets =
    map (host: {
      targets = ["${host}.ts.${dns}:9100"];
      labels = {inherit host;};
    })
    monitoredHosts;

  ciJobScrapeTargets = lib.filter (target: target.labels.host == "radon") scrapeTargets;
  llmScrapeTargets = lib.filter (target: target.labels.host == "xenon") scrapeTargets;

  dashboard = pkgs.writeTextDir "homelab-overview.json" (builtins.toJSON {
    uid = "homelab-overview";
    title = "Homelab Overview";
    tags = ["homelab" "provisioned"];
    timezone = "browser";
    schemaVersion = 41;
    editable = false;
    refresh = "30s";
    time = {
      from = "now-6h";
      to = "now";
    };
    templating.list = [];
    annotations.list = [];
    panels = [
      {
        id = 1;
        title = "Online";
        type = "stat";
        gridPos = {
          x = 0;
          y = 0;
          w = 12;
          h = 8;
        };
        datasource = {
          type = "prometheus";
          uid = "victoriametrics";
        };
        targets = [
          {
            refId = "A";
            expr = "up{job=\"nodes\"}";
            legendFormat = "{{host}}";
            instant = true;
          }
        ];
        options = {
          colorMode = "background";
          graphMode = "none";
          justifyMode = "auto";
          orientation = "horizontal";
          reduceOptions = {
            calcs = ["lastNotNull"];
            fields = "";
            values = false;
          };
          textMode = "value_and_name";
          wideLayout = true;
          text = {
            titleSize = 20;
            valueSize = 28;
          };
        };
        fieldConfig = {
          defaults = {
            mappings = [
              {
                type = "value";
                options = {
                  "0" = {
                    text = "Offline";
                    color = "red";
                  };
                  "1" = {
                    text = "Online";
                    color = "green";
                  };
                };
              }
            ];
            thresholds = {
              mode = "absolute";
              steps = [
                {
                  color = "red";
                  value = null;
                }
                {
                  color = "green";
                  value = 1;
                }
              ];
            };
          };
          overrides = [];
        };
      }
      {
        id = 2;
        title = "CPU usage";
        type = "timeseries";
        gridPos = {
          x = 0;
          y = 8;
          w = 12;
          h = 8;
        };
        datasource = {
          type = "prometheus";
          uid = "victoriametrics";
        };
        targets = [
          {
            refId = "A";
            expr = "100 - (avg by (host) (rate(node_cpu_seconds_total{mode=\"idle\"}[$__rate_interval])) * 100)";
            legendFormat = "{{host}}";
          }
        ];
        fieldConfig = {
          defaults = {
            unit = "percent";
            min = 0;
            max = 100;
          };
          overrides = [];
        };
      }
      {
        id = 3;
        title = "Memory usage";
        type = "timeseries";
        gridPos = {
          x = 12;
          y = 8;
          w = 12;
          h = 8;
        };
        datasource = {
          type = "prometheus";
          uid = "victoriametrics";
        };
        targets = [
          {
            refId = "A";
            expr = "100 * (1 - node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes)";
            legendFormat = "{{host}}";
          }
        ];
        fieldConfig = {
          defaults = {
            unit = "percent";
            min = 0;
            max = 100;
          };
          overrides = [];
        };
      }
      {
        id = 12;
        title = "CPU temperature";
        description = "Hottest reported CPU package/core sensor per host; non-CPU thermal sensors are excluded.";
        type = "timeseries";
        gridPos = {
          x = 0;
          y = 16;
          w = 24;
          h = 7;
        };
        datasource = {
          type = "prometheus";
          uid = "victoriametrics";
        };
        targets = [
          {
            refId = "A";
            expr = "max by (host) (node_hwmon_temp_celsius{chip=~\"platform_coretemp_0|pci0000:00_0000:00:18_3\"})";
            legendFormat = "{{host}}";
          }
        ];
        fieldConfig = {
          defaults = {
            unit = "celsius";
            min = 0;
            thresholds = {
              mode = "absolute";
              steps = [
                {
                  color = "green";
                  value = null;
                }
                {
                  color = "orange";
                  value = 70;
                }
                {
                  color = "red";
                  value = 85;
                }
              ];
            };
          };
          overrides = [];
        };
      }
      {
        id = 4;
        title = "Network received";
        type = "timeseries";
        gridPos = {
          x = 0;
          y = 23;
          w = 12;
          h = 8;
        };
        datasource = {
          type = "prometheus";
          uid = "victoriametrics";
        };
        targets = [
          {
            refId = "A";
            expr = "sum by (host) (rate(node_network_receive_bytes_total{device!~\"lo|tailscale0\"}[$__rate_interval]))";
            legendFormat = "{{host}}";
          }
        ];
        fieldConfig = {
          defaults.unit = "Bps";
          overrides = [];
        };
      }
      {
        id = 5;
        title = "Network sent";
        type = "timeseries";
        gridPos = {
          x = 12;
          y = 23;
          w = 12;
          h = 8;
        };
        datasource = {
          type = "prometheus";
          uid = "victoriametrics";
        };
        targets = [
          {
            refId = "A";
            expr = "sum by (host) (rate(node_network_transmit_bytes_total{device!~\"lo|tailscale0\"}[$__rate_interval]))";
            legendFormat = "{{host}}";
          }
        ];
        fieldConfig = {
          defaults.unit = "Bps";
          overrides = [];
        };
      }

      {
        id = 11;
        title = "Aggregate tailnet throughput";
        description = "Sum of tailscale0 transmit rates. Counting only the sending side avoids double-counting traffic received by another monitored host.";
        type = "timeseries";
        gridPos = {
          x = 0;
          y = 31;
          w = 24;
          h = 7;
        };
        datasource = {
          type = "prometheus";
          uid = "victoriametrics";
        };
        targets = [
          {
            refId = "A";
            expr = "sum(rate(node_network_transmit_bytes_total{device=\"tailscale0\"}[$__rate_interval]))";
            legendFormat = "tailnet throughput";
          }
        ];
        fieldConfig = {
          defaults = {
            unit = "Bps";
            min = 0;
          };
          overrides = [];
        };
      }
      {
        id = 6;
        title = "Filesystem usage";
        type = "timeseries";
        gridPos = {
          x = 0;
          y = 38;
          w = 12;
          h = 8;
        };
        datasource = {
          type = "prometheus";
          uid = "victoriametrics";
        };
        targets = [
          {
            refId = "A";
            expr = "100 * (1 - node_filesystem_avail_bytes{mountpoint=~\"/|/mnt/media\",fstype!~\"tmpfs|overlay\"} / node_filesystem_size_bytes{mountpoint=~\"/|/mnt/media\",fstype!~\"tmpfs|overlay\"})";
            legendFormat = "{{host}}: {{mountpoint}}";
          }
        ];
        fieldConfig = {
          defaults = {
            unit = "percent";
            min = 0;
            max = 100;
            custom.spanNulls = true;
          };
          overrides = [];
        };
      }
      {
        id = 7;
        title = "Nix store size";
        type = "timeseries";
        gridPos = {
          x = 12;
          y = 38;
          w = 12;
          h = 8;
        };
        datasource = {
          type = "prometheus";
          uid = "victoriametrics";
        };
        targets = [
          {
            refId = "A";
            expr = "nix_store_disk_bytes";
            legendFormat = "{{host}}";
          }
        ];
        fieldConfig = {
          defaults = {
            unit = "bytes";
            custom.spanNulls = true;
          };
          overrides = [];
        };
      }
      {
        id = 8;
        title = "slskd uploads";
        description = "Completed uploads since monitoring was enabled.";
        type = "stat";
        gridPos = {
          x = 12;
          y = 0;
          w = 12;
          h = 8;
        };
        datasource = {
          type = "prometheus";
          uid = "victoriametrics";
        };
        targets = [
          {
            refId = "A";
            expr = "increase(slskd_upload_files_total[24h])";
            legendFormat = "24h files";
            instant = true;
          }
          {
            refId = "B";
            expr = "increase(slskd_upload_bytes_total[24h])";
            legendFormat = "24h transferred";
            instant = true;
          }
          {
            refId = "C";
            expr = "increase(slskd_upload_files_total[7d])";
            legendFormat = "7d files";
            instant = true;
          }
          {
            refId = "D";
            expr = "increase(slskd_upload_bytes_total[7d])";
            legendFormat = "7d transferred";
            instant = true;
          }
          {
            refId = "E";
            expr = "slskd_upload_files_total";
            legendFormat = "All time files";
            instant = true;
          }
          {
            refId = "F";
            expr = "slskd_upload_bytes_total";
            legendFormat = "All time transferred";
            instant = true;
          }
        ];
        options = {
          colorMode = "none";
          graphMode = "none";
          justifyMode = "center";
          orientation = "horizontal";
          textMode = "value_and_name";
          wideLayout = true;
          text = {
            titleSize = 16;
            valueSize = 24;
          };
          reduceOptions = {
            calcs = ["lastNotNull"];
            fields = "";
            values = false;
          };
        };
        fieldConfig = {
          defaults.decimals = 0;
          overrides = [
            {
              matcher = {
                id = "byFrameRefID";
                options = "B";
              };
              properties = [
                {
                  id = "unit";
                  value = "bytes";
                }
              ];
            }
            {
              matcher = {
                id = "byFrameRefID";
                options = "D";
              };
              properties = [
                {
                  id = "unit";
                  value = "bytes";
                }
              ];
            }
            {
              matcher = {
                id = "byFrameRefID";
                options = "F";
              };
              properties = [
                {
                  id = "unit";
                  value = "bytes";
                }
              ];
            }
          ];
        };
      }
      {
        id = 13;
        title = "Radon load during GitLab jobs";
        description = "Radon CPU and memory usage. Shaded regions mark when GitLab Runner was executing a job.";
        type = "timeseries";
        interval = "5s";
        gridPos = {
          x = 0;
          y = 46;
          w = 24;
          h = 9;
        };
        datasource = {
          type = "prometheus";
          uid = "victoriametrics";
        };
        # The shading query is first (refId A) so it is drawn behind the lines.
        targets = [
          {
            refId = "A";
            expr = "max_over_time(gitlab_runner_job_info{host=\"radon\",job=\"ci-jobs\"}[$__interval])";
            legendFormat = "{{job_name}} #{{job_id}}";
          }
          {
            refId = "B";
            expr = "100 - (avg(rate(node_cpu_seconds_total{host=\"radon\",mode=\"idle\"}[$__rate_interval])) * 100)";
            legendFormat = "CPU";
          }
          {
            refId = "C";
            expr = "100 * (1 - node_memory_MemAvailable_bytes{host=\"radon\"} / node_memory_MemTotal_bytes{host=\"radon\"})";
            legendFormat = "Memory";
          }
        ];
        options.tooltip.mode = "multi";
        fieldConfig = {
          defaults = {
            unit = "percent";
            min = 0;
            max = 100;
          };
          overrides = [
            {
              matcher = {
                id = "byFrameRefID";
                options = "A";
              };
              properties = [
                # A different unit gives this series its own 0-1 y-scale, so the
                # bars fill the full panel height regardless of the 0-100 scale.
                {
                  id = "unit";
                  value = "none";
                }
                {
                  id = "min";
                  value = 0;
                }
                {
                  id = "max";
                  value = 1;
                }
                {
                  id = "color";
                  value = {
                    mode = "shades";
                    fixedColor = "orange";
                  };
                }
                {
                  id = "custom.drawStyle";
                  value = "bars";
                }
                {
                  id = "custom.barWidthFactor";
                  value = 1;
                }
                {
                  id = "custom.fillOpacity";
                  value = 25;
                }
                {
                  id = "custom.lineWidth";
                  value = 0;
                }
                {
                  id = "custom.axisPlacement";
                  value = "hidden";
                }
              ];
            }
            {
              matcher = {
                id = "byFrameRefID";
                options = "B";
              };
              properties = [
                {
                  id = "color";
                  value = {
                    mode = "fixed";
                    fixedColor = "blue";
                  };
                }
              ];
            }
            {
              matcher = {
                id = "byFrameRefID";
                options = "C";
              };
              properties = [
                {
                  id = "color";
                  value = {
                    mode = "fixed";
                    fixedColor = "purple";
                  };
                }
              ];
            }
          ];
        };
      }
      {
        id = 14;
        title = "Xenon load during local LLM activity";
        description = "Xenon CPU, memory, GPU utilization, and GPU VRAM usage. Shaded regions mark when llama-cpp was active.";
        type = "timeseries";
        interval = "5s";
        gridPos = {
          x = 0;
          y = 55;
          w = 24;
          h = 9;
        };
        datasource = {
          type = "prometheus";
          uid = "victoriametrics";
        };
        targets = [
          {
            refId = "A";
            expr = "max_over_time(llama_cpp_info{host=\"xenon\",job=\"llm-metrics\"}[$__interval])";
            legendFormat = "llama-cpp ({{model}})";
          }
          {
            refId = "B";
            expr = "100 - (avg(rate(node_cpu_seconds_total{host=\"xenon\",mode=\"idle\"}[$__rate_interval])) * 100)";
            legendFormat = "CPU";
          }
          {
            refId = "C";
            expr = "100 * (1 - node_memory_MemAvailable_bytes{host=\"xenon\"} / node_memory_MemTotal_bytes{host=\"xenon\"})";
            legendFormat = "Memory";
          }
          {
            refId = "D";
            expr = "max_over_time(amdgpu_gpu_busy_percent{host=\"xenon\",job=\"llm-metrics\"}[$__interval])";
            legendFormat = "GPU";
          }
          {
            refId = "E";
            expr = "100 * max_over_time(amdgpu_vram_used_bytes{host=\"xenon\",job=\"llm-metrics\"}[$__interval]) / max_over_time(amdgpu_vram_total_bytes{host=\"xenon\",job=\"llm-metrics\"}[$__interval])";
            legendFormat = "GPU VRAM";
          }
        ];
        options.tooltip.mode = "multi";
        fieldConfig = {
          defaults = {
            unit = "percent";
            min = 0;
            max = 100;
          };
          overrides = [
            {
              matcher = {
                id = "byFrameRefID";
                options = "A";
              };
              properties = [
                {
                  id = "unit";
                  value = "none";
                }
                {
                  id = "min";
                  value = 0;
                }
                {
                  id = "max";
                  value = 1;
                }
                {
                  id = "color";
                  value = {
                    mode = "shades";
                    fixedColor = "orange";
                  };
                }
                {
                  id = "custom.drawStyle";
                  value = "bars";
                }
                {
                  id = "custom.barWidthFactor";
                  value = 1;
                }
                {
                  id = "custom.fillOpacity";
                  value = 25;
                }
                {
                  id = "custom.lineWidth";
                  value = 0;
                }
                {
                  id = "custom.axisPlacement";
                  value = "hidden";
                }
              ];
            }
            {
              matcher = {
                id = "byFrameRefID";
                options = "B";
              };
              properties = [
                {
                  id = "color";
                  value = {
                    mode = "fixed";
                    fixedColor = "blue";
                  };
                }
              ];
            }
            {
              matcher = {
                id = "byFrameRefID";
                options = "C";
              };
              properties = [
                {
                  id = "color";
                  value = {
                    mode = "fixed";
                    fixedColor = "purple";
                  };
                }
              ];
            }
            {
              matcher = {
                id = "byFrameRefID";
                options = "D";
              };
              properties = [
                {
                  id = "color";
                  value = {
                    mode = "fixed";
                    fixedColor = "green";
                  };
                }
              ];
            }
            {
              matcher = {
                id = "byFrameRefID";
                options = "E";
              };
              properties = [
                {
                  id = "color";
                  value = {
                    mode = "fixed";
                    fixedColor = "yellow";
                  };
                }
              ];
            }
          ];
        };
      }
    ];
  });
in {
  age.secrets.grafana-secret-key = {
    file = ../../secrets/grafana-secret-key.age;
    owner = "grafana";
    group = "grafana";
  };

  services.victoriametrics = {
    enable = true;
    listenAddress = "127.0.0.1:${toString victoriaMetricsPort}";
    retentionPeriod = "7d";
    extraOptions = [
      "-memory.allowedBytes=512MiB"
      "-storage.minFreeDiskSpaceBytes=512MiB"
    ];
    prometheusConfig = {
      global.scrape_interval = "30s";
      scrape_configs = [
        {
          job_name = "nodes";
          static_configs = scrapeTargets;
        }
        {
          job_name = "ci-jobs";
          scrape_interval = "5s";
          params."collect[]" = ["textfile"];
          static_configs = ciJobScrapeTargets;
          metric_relabel_configs = [
            {
              source_labels = ["__name__"];
              regex = "gitlab_runner_.*";
              action = "keep";
            }
          ];
        }
        {
          job_name = "llm-metrics";
          scrape_interval = "5s";
          params."collect[]" = ["textfile"];
          static_configs = llmScrapeTargets;
          metric_relabel_configs = [
            {
              source_labels = ["__name__"];
              regex = "(llama_cpp_.*|amdgpu_.*)";
              action = "keep";
            }
          ];
        }
      ];
    };
  };

  services.grafana = {
    enable = true;
    settings = {
      server = {
        http_addr = "127.0.0.1";
        http_port = grafanaPort;
        domain = grafanaHost;
        root_url = "https://${grafanaHost}";
      };
      analytics = {
        reporting_enabled = false;
        check_for_updates = false;
      };
      security = {
        disable_initial_admin_creation = true;
        secret_key = "$__file{${config.age.secrets.grafana-secret-key.path}}";
      };
      users = {
        allow_sign_up = false;
        auto_assign_org_role = "Viewer";
      };
      auth.disable_login_form = true;
      "auth.proxy" = {
        enabled = true;
        header_name = "Remote-User";
        header_property = "username";
        auto_sign_up = true;
        sync_ttl = 60;
        whitelist = "127.0.0.1";
        headers = "Email:Remote-Email Name:Remote-Name";
      };
    };
    provision = {
      enable = true;
      datasources.settings = {
        apiVersion = 1;
        prune = true;
        datasources = [
          {
            name = "VictoriaMetrics";
            uid = "victoriametrics";
            type = "prometheus";
            access = "proxy";
            url = "http://127.0.0.1:${toString victoriaMetricsPort}";
            isDefault = true;
            editable = false;
          }
        ];
      };
      dashboards.settings = {
        apiVersion = 1;
        providers = [
          {
            name = "Homelab";
            disableDeletion = true;
            editable = true;
            options.path = dashboard;
          }
        ];
      };
    };
  };

  services.caddy.virtualHosts.${grafanaHost}.extraConfig = ''
    forward_auth 127.0.0.1:9091 {
      uri /api/authz/forward-auth
      header_up X-Forwarded-Proto https
      copy_headers Remote-User Remote-Groups Remote-Email Remote-Name
    }
    reverse_proxy 127.0.0.1:${toString grafanaPort}
  '';
}
