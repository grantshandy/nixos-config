# Perses and VictoriaMetrics: the fleet's metrics store and dashboards.
#
# This file owns only the plumbing -- the fleet-wide scrape job, the data
# directory, the Perses service and the project its resources live in. Nothing
# here knows which machines run CI or an LLM, or what those machines' metrics
# are called; a service contributes both halves of its own monitoring instead:
#
#   - `fleet.monitoring.scrapeJobs` for a job with its own hosts, interval and
#     metric filter, when the fleet-wide `nodes` job is too coarse.
#   - `fleet.monitoring.dashboards` for one dashboard of its own, so services
#     cannot collide in each other's panels. The fleet overview is just another
#     contributor, from `dashboard.nix` next door.
#
# That keeps a service's metrics model, the code that publishes it, the job that
# collects it and the panels that read it together in one file.
{
  config,
  lib,
  ...
}: let
  victoriaMetricsPort = 8428;
  persesPort = 3001;
  projectName = "homelab";
in {
  options.fleet.monitoring.victoriaMetricsUrl = lib.mkOption {
    type = lib.types.str;
    readOnly = true;
    description = ''
      Tailnet URL for VictoriaMetrics' import endpoints. Services that want an
      event to show up immediately, rather than waiting for the next scrape,
      push samples here directly (e.g. with `curl .../api/v1/import/prometheus`).
    '';
  };

  options.fleet.monitoring.project = lib.mkOption {
    type = lib.types.str;
    readOnly = true;
    description = "Perses project every provisioned dashboard belongs to.";
  };

  options.fleet.monitoring.scrapeJobs = lib.mkOption {
    type = lib.types.attrsOf (lib.types.submodule ({name, ...}: {
      options = {
        name = lib.mkOption {
          type = lib.types.str;
          internal = true;
          default = name;
          description = "Prometheus `job` label, taken from the attribute name.";
        };
        hosts = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          description = ''
            Registry host names to scrape. A job with no hosts is dropped, so a
            service whose hosts are derived from a tag nobody carries costs
            nothing.
          '';
        };
        interval = lib.mkOption {
          type = lib.types.str;
          default = "15s";
          description = "Scrape interval, for metrics that need finer resolution than the default.";
        };
        collectors = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [];
          description = ''
            node_exporter collectors to restrict the scrape to, e.g.
            `["textfile"]`. Empty means every enabled collector, which is
            wasteful for a job that only wants one metric family.
          '';
        };
        keepMetrics = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [];
          description = ''
            Metric name patterns to keep; everything else the scrape returns is
            dropped. Empty keeps all of them.
          '';
        };
      };
    }));
    default = {};
    description = ''
      Extra scrape jobs on top of the fleet-wide `nodes` job, keyed by job name.
      A service that publishes metrics needing their own interval or their own
      filter declares the job here, next to the code that writes those metrics
      and to the dashboard that reads them.
    '';
  };

  options.fleet.monitoring.dashboards = lib.mkOption {
    type = lib.types.attrsOf (lib.types.submodule ({name, ...}: {
      options = {
        name = lib.mkOption {
          type = lib.types.str;
          internal = true;
          default = name;
          description = "Perses resource name, taken from the attribute name.";
        };
        title = lib.mkOption {
          type = lib.types.str;
          description = "Dashboard title shown in Perses.";
        };
        duration = lib.mkOption {
          type = lib.types.str;
          default = "6h";
          description = "Default time range the dashboard opens on.";
        };
        refreshInterval = lib.mkOption {
          type = lib.types.str;
          default = "30s";
          description = "Default auto-refresh interval.";
        };
        variables = lib.mkOption {
          type = lib.types.listOf lib.types.attrs;
          default = [];
          description = "Perses dashboard variables, e.g. from `_lib.nix`'s `labelVariable`.";
        };
        panels = lib.mkOption {
          type = lib.types.attrsOf lib.types.attrs;
          description = ''
            Perses panels keyed by the name `layouts` refers to them by. Build
            them with `_lib.nix`'s `timeSeries`, `gauge` or `stat` rather than
            by hand.
          '';
        };
        layouts = lib.mkOption {
          type = lib.types.listOf lib.types.attrs;
          description = "Perses layouts, one per section; see `_lib.nix`'s `group`.";
        };
      };
    }));
    default = {};
    description = ''
      Dashboards provisioned into the homelab Perses project, keyed by resource
      name. Each is a dashboard of its own, so a service declares its whole
      visualization without having to fit into a shared grid.
    '';
  };

  config.fleet.monitoring = {
    project = projectName;
    victoriaMetricsUrl = "http://${config.fleet.services.Perses.host}.ts.${config.fleet.identity.homelab.dns}:${toString victoriaMetricsPort}";
  };

  config.fleet.services.Perses = {
    host = config.fleet.edgeHost;
    description = "Homelab monitoring";
    subdomain = "perses";
    path = "/projects/${projectName}";
    auth = "session";
    port = persesPort;
    localProxy.port = persesPort;
    directory = true;
    bookmark = false;
  };

  config.flake.modules.nixos.Perses =
    ({
      hosts,
      persesService,
      scrapeJobs,
      dashboards,
      exporterPort,
      victoriaMetricsPort,
      persesPort,
      projectName,
      extraStorageRoot,
    }: {
      config,
      lib,
      pkgs,
      utils,
      ...
    }: let
      dns = config.identity.homelab.dns;
      # A storage root need not be its own filesystem -- on a host without a
      # spare drive it is a directory on /, and systemd generates no `.mount`
      # for it. Depend on one only when it exists; the `RequiresMountsFor` below
      # orders against the real mount either way.
      extraStorageMountUnits =
        lib.optional (config.fileSystems ? ${extraStorageRoot})
        "${utils.escapeSystemdPath extraStorageRoot}.mount";
      # DynamicUser + StateDirectory backs "/var/lib/victoriametrics" with a
      # private bind mount from "/var/lib/private/victoriametrics" (only
      # visible inside the service's own mount namespace), so that's the real
      # path to redirect onto the external drive.
      victoriaMetricsStatePath = "/var/lib/private/victoriametrics";
      victoriaMetricsDataMountUnit = "${utils.escapeSystemdPath victoriaMetricsStatePath}.mount";
      victoriaMetricsDataDir = "${extraStorageRoot}/victoriametrics";

      mapPanel = pkgs.callPackage ../../../perses-map-panel {};
      pluginArchive = pkgs.symlinkJoin {
        name = "perses-plugin-archive-with-map";
        paths = [pkgs.perses.pluginsArchive mapPanel];
      };

      monitoredHosts =
        hosts
        |> lib.filterAttrs (_: host: host.tailscale.enable)
        |> lib.attrNames;

      # The `host` label is what every dashboard groups by; the target address
      # itself only ever appears as `instance`.
      staticConfig = hostNames:
        map (host: {
          targets = ["${host}.ts.${dns}:${toString exporterPort}"];
          labels = {inherit host;};
        })
        hostNames;

      serviceScrapeConfigs =
        scrapeJobs
        |> lib.attrValues
        |> lib.filter (job: job.hosts != [])
        |> map (job:
          {
            job_name = job.name;
            scrape_interval = job.interval;
            static_configs = staticConfig job.hosts;
          }
          // lib.optionalAttrs (job.collectors != []) {
            params."collect[]" = job.collectors;
          }
          // lib.optionalAttrs (job.keepMetrics != []) {
            metric_relabel_configs = [
              {
                source_labels = ["__name__"];
                regex = "(${lib.concatStringsSep "|" job.keepMetrics})";
                action = "keep";
              }
            ];
          });

      datasourceName = "victoriametrics";

      # Provisioning reads every file in the configured folders, so each
      # resource is its own single-file store path.
      resourceFile = fileName: resource: pkgs.writeTextDir fileName (builtins.toJSON resource);

      project = resourceFile "project.json" {
        kind = "Project";
        metadata.name = projectName;
        spec.display.name = "Homelab";
      };

      # Proxied rather than pointed straight at the tailnet URL, so browsers
      # reach VictoriaMetrics through the authenticated Perses origin and the
      # metrics port never has to be published at the edge.
      datasource = resourceFile "datasource.json" {
        kind = "Datasource";
        metadata = {
          name = datasourceName;
          project = projectName;
        };
        spec = {
          default = true;
          plugin = {
            kind = "PrometheusDatasource";
            spec.proxy = {
              kind = "HTTPProxy";
              spec.url = "http://127.0.0.1:${toString victoriaMetricsPort}";
            };
          };
        };
      };

      dashboardFile = dashboard:
        resourceFile "dashboard-${dashboard.name}.json" {
          kind = "Dashboard";
          metadata = {
            inherit (dashboard) name;
            project = projectName;
          };
          spec =
            {
              display.name = dashboard.title;
              inherit (dashboard) duration refreshInterval panels layouts;
            }
            // lib.optionalAttrs (dashboard.variables != []) {inherit (dashboard) variables;};
        };

      dashboardFiles = map dashboardFile (lib.attrValues dashboards);
    in {
      # Store VictoriaMetrics' data on the external USB drive rather than the
      # SD card, by bind-mounting its data directory onto the drive. The
      # subdirectory has to exist before the bind mount runs, so the mount waits
      # on tmpfiles. Starting it through multi-user.target keeps it out of the
      # local-fs.target transaction and avoids an ordering cycle: tmpfiles runs
      # after local-fs.target.
      systemd.tmpfiles.rules = [
        "d ${victoriaMetricsDataDir} 0700 root root - -"
      ];

      fileSystems.${victoriaMetricsStatePath} = {
        device = victoriaMetricsDataDir;
        fsType = "none";
        options = [
          "bind"
          "x-systemd.after=systemd-tmpfiles-setup.service"
          "x-systemd.wanted-by=multi-user.target"
        ];
      };

      systemd.services.victoriametrics = {
        bindsTo = extraStorageMountUnits ++ [victoriaMetricsDataMountUnit];
        after = extraStorageMountUnits ++ [victoriaMetricsDataMountUnit];
        unitConfig.RequiresMountsFor = [extraStorageRoot victoriaMetricsStatePath];
      };

      services.victoriametrics = {
        enable = true;
        # Bound to all interfaces (not just loopback) so hosts on the tailnet
        # can push samples directly into `fleet.monitoring.victoriaMetricsUrl`
        # instead of waiting for the next scrape. The firewall below is what
        # actually restricts this to the tailnet, same trust boundary as the
        # unauthenticated node-exporter/9100 scrape target.
        listenAddress = "0.0.0.0:${toString victoriaMetricsPort}";
        prometheusConfig = {
          global.scrape_interval = "15s";
          scrape_configs =
            [
              {
                job_name = "nodes";
                static_configs = staticConfig monitoredHosts;
              }
            ]
            ++ serviceScrapeConfigs;
        };
      };

      networking.firewall.interfaces.tailscale0.allowedTCPPorts = [victoriaMetricsPort];

      services.perses = {
        enable = true;
        port = persesPort;
        listenAddress = "127.0.0.1";
        settings = {
          # Perses re-reads the folders on this interval, so an edited-in-place
          # dashboard reverts rather than drifting away from this repo.
          provisioning = {
            folders = [project datasource] ++ dashboardFiles;
            interval = "1h";
          };
          # The edge is the only way in, and it authenticates every request;
          # Perses itself has no users.
          security.enable_auth = false;
        };
      };

      services.caddy.virtualHosts.${persesService.fqdn}.extraConfig = ''
        forward_auth 127.0.0.1:9091 {
          uri /api/authz/forward-auth
          header_up X-Forwarded-Proto https
          copy_headers Remote-User Remote-Groups Remote-Email Remote-Name
        }
        reverse_proxy 127.0.0.1:${toString persesPort}
      '';
    }) {
      hosts = config.fleet.hosts;
      persesService = config.fleet.services.Perses;
      inherit (config.fleet.monitoring) scrapeJobs dashboards exporterPort;
      inherit victoriaMetricsPort persesPort projectName;
      extraStorageRoot = config.fleet.hosts.${config.fleet.services.Perses.host}.extraStorageRoot;
    };
}
