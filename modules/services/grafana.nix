# Grafana and VictoriaMetrics: the fleet's metrics store and dashboard.
#
# Which machines are scraped, and which of them count as CI or LLM hosts, all
# come from the registry's tags rather than from host names spelled out in the
# dashboard definition.
#
# Services that publish their own metrics contribute a dashboard panel
# through `fleet.monitoring.panels` instead of editing this file, so the
# metrics model, publishing, and visualization live together in one module.
# Custom panels are stacked full-width below the core panels, ordered by their
# `order` field (ties break alphabetically by attribute name).
{
  config,
  lib,
  ...
}: {
  options.fleet.monitoring.panels = lib.mkOption {
    type = lib.types.attrsOf (lib.types.submodule ({name, ...}: {
      options = {
        name = lib.mkOption {
          type = lib.types.str;
          internal = true;
          default = name;
        };
        title = lib.mkOption {
          type = lib.types.str;
          description = "Panel title.";
        };
        description = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          default = null;
          description = "Panel description shown on hover.";
        };
        height = lib.mkOption {
          type = lib.types.ints.positive;
          default = 8;
          description = "Panel height in grid rows.";
        };
        order = lib.mkOption {
          type = lib.types.int;
          default = 0;
          description = "Stacking priority among custom panels, lowest first. Ties break alphabetically by attribute name.";
        };
        panel = lib.mkOption {
          type = lib.types.attrs;
          description = ''
            Raw Grafana panel attrs (type, interval, datasource, targets,
            options, fieldConfig, ...). Do not set id, title, description, or
            gridPos here; the dashboard assigns those.
          '';
        };
      };
    }));
    default = {};
    description = "Custom metrics panels contributed by service modules, appended full-width to the bottom of the homelab dashboard.";
  };

  config.fleet.services.Grafana = {
    host = config.fleet.edgeHost;
    description = "Homelab monitoring";
    subdomain = "monitor";
    path = "/d/homelab-overview/";
    auth = "session";
    port = 3000;
    localProxy.port = 3000;
  };

  config.flake.modules.nixos.Grafana =
    ({
      hosts,
      grafanaService,
      customPanels,
    }: {
      config,
      lib,
      pkgs,
      ...
    }: let
      dns = config.identity.homelab.dns;
      grafanaPort = 3000;
      victoriaMetricsPort = 8428;

      grafanaHost = grafanaService.fqdn;
      monitoredHosts =
        hosts
        |> lib.filterAttrs (_: host: host.tailscale.enable)
        |> lib.attrNames;

      scrapeTargets =
        map (host: {
          targets = ["${host}.ts.${dns}:9100"];
          labels = {inherit host;};
        })
        monitoredHosts;

      targetsTagged = tag: lib.filter (target: lib.elem tag hosts.${target.labels.host}.tags) scrapeTargets;
      ciJobScrapeTargets = targetsTagged "ci";
      llmScrapeTargets = targetsTagged "llm";

      hostColorPalette = ["green" "blue" "orange" "purple" "red" "yellow" "light-blue" "light-red"];
      hostColorOverrides =
        lib.imap0 (i: host: {
          matcher = {
            id = "byRegexp";
            options = "^${host} (tx|rx)$";
          };
          properties = [
            {
              id = "color";
              value = {
                mode = "fixed";
                fixedColor = builtins.elemAt hostColorPalette (lib.mod i (builtins.length hostColorPalette));
              };
            }
          ];
        })
        monitoredHosts;

      customPanelsSorted =
        lib.attrValues customPanels
        |> lib.sort (a: b: a.order < b.order || (a.order == b.order && a.name < b.name));

      customPanelsResolved =
        lib.foldl' (acc: cfg: {
          nextId = acc.nextId + 1;
          y = acc.y + cfg.height;
          panels =
            acc.panels
            ++ [
              (cfg.panel
                // {
                  inherit (cfg) title;
                  id = acc.nextId;
                  gridPos = {
                    x = 0;
                    y = acc.y;
                    w = 24;
                    h = cfg.height;
                  };
                }
                // lib.optionalAttrs (cfg.description != null) {inherit (cfg) description;})
            ];
        }) {
          nextId = 100;
          y = 46;
          panels = [];
        }
        customPanelsSorted;

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
        panels =
          [
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
                y = 16;
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
                x = 12;
                y = 24;
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
              title = "Network traffic";
              description = "Received above the axis, sent mirrored below it";
              type = "timeseries";
              gridPos = {
                x = 0;
                y = 8;
                w = 12;
                h = 16;
              };
              datasource = {
                type = "prometheus";
                uid = "victoriametrics";
              };
              targets = [
                {
                  refId = "A";
                  expr = "sum by (host) (rate(node_network_receive_bytes_total{device!~\"lo|tailscale0\"}[$__rate_interval]))";
                  legendFormat = "{{host}} rx";
                }
                {
                  refId = "B";
                  expr = "-sum by (host) (rate(node_network_transmit_bytes_total{device!~\"lo|tailscale0\"}[$__rate_interval]))";
                  legendFormat = "{{host}} tx";
                }
              ];
              fieldConfig = {
                defaults.unit = "Bps";
                overrides = hostColorOverrides;
              };
            }
            {
              id = 11;
              title = "Aggregate tailnet throughput";
              description = "Sum of tailscale0 transmit rates. Counting only the sending side avoids double-counting traffic received by another monitored host.";
              type = "timeseries";
              gridPos = {
                x = 0;
                y = 24;
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
                h = 16;
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
          ]
          ++ customPanelsResolved.panels;
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
    }) {
      hosts = config.fleet.hosts;
      grafanaService = config.fleet.services.Grafana;
      customPanels = config.fleet.monitoring.panels;
    };
}
