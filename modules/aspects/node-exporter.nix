# Metrics agent. Every host runs it; services that export custom metrics write
# textfiles into `fleet.monitoring.textfileDir`, which is published at the flake
# level so those services can reference it without a _module.args channel.
{lib, ...}: let
  exporterPort = 9100;
  textfileDir = "/var/lib/node-exporter-textfile";
in {
  options.fleet.monitoring.textfileDir = lib.mkOption {
    type = lib.types.str;
    readOnly = true;
    description = "Directory node_exporter scrapes for textfile-collector metrics.";
  };

  options.fleet.monitoring.exporterPort = lib.mkOption {
    type = lib.types.port;
    readOnly = true;
    description = "Port every host's node_exporter listens on, i.e. what the metrics store scrapes.";
  };

  config = {
    fleet.monitoring.textfileDir = textfileDir;
    fleet.monitoring.exporterPort = exporterPort;
    fleet.aspects.node-exporter.default = true;

    flake.modules.nixos.node-exporter = {pkgs, ...}: let
      collectNixStoreSize = pkgs.writeShellApplication {
        name = "collect-nix-store-size";
        runtimeInputs = [pkgs.coreutils];
        text = ''
          bytes="$(du --summarize --block-size=1 /nix/store | cut --fields=1)"
          output="${textfileDir}/nix-store.prom"
          temporary="$(mktemp --tmpdir=${textfileDir} .nix-store.prom.XXXXXX)"

          printf '%s\n' \
            '# HELP nix_store_disk_bytes Disk space used by the Nix store.' \
            '# TYPE nix_store_disk_bytes gauge' \
            "nix_store_disk_bytes $bytes" \
            > "$temporary"
          chmod 0644 "$temporary"
          mv --force "$temporary" "$output"
        '';
      };
    in {
      services.prometheus.exporters.node = {
        enable = true;
        listenAddress = "0.0.0.0";
        port = exporterPort;
        enabledCollectors = ["systemd"];
        extraFlags = ["--collector.textfile.directory=${textfileDir}"];
      };

      networking.firewall.interfaces.tailscale0.allowedTCPPorts = [exporterPort];

      systemd.tmpfiles.rules = [
        "d ${textfileDir} 2775 root node-exporter - -"
      ];

      systemd.services.collect-nix-store-size = {
        description = "Export Nix store disk usage for node_exporter";
        serviceConfig = {
          Type = "oneshot";
          ExecStart = lib.getExe collectNixStoreSize;
          PrivateTmp = true;
          ProtectHome = true;
          ProtectSystem = "strict";
          ReadWritePaths = [textfileDir];
        };
      };

      systemd.timers.collect-nix-store-size = {
        description = "Periodically measure Nix store disk usage";
        wantedBy = ["timers.target"];
        timerConfig = {
          OnBootSec = "5min";
          OnUnitActiveSec = "30min";
          RandomizedDelaySec = "2min";
          Persistent = true;
        };
      };
    };
  };
}
