# slskd, the Soulseek client that feeds Lidarr's download directories, plus
# desktop notifications for its completed uploads.
#
# Which machine runs the ntfy server is not configured anywhere here: it is read
# off the service registry, so moving slskd to another host moves the publisher
# with it and re-points every subscriber. The server and client are separate
# aspects enrolled by `hosts`/`tags`, which is why neither module contains any
# "am I the right host?" guard -- it is only ever evaluated where it belongs.
{config, ...}: let
  webPort = 5030;
  listenPort = 55125;
  media = config.fleet.media;
  service = config.fleet.services.slskd;
  nodeExporterTextfileDir = config.fleet.monitoring.textfileDir;
  victoriaMetricsUrl = config.fleet.monitoring.victoriaMetricsUrl;

  notifyStateDirectory = "slskd-notify";
  notifySpoolDir = "/var/lib/${notifyStateDirectory}";
  ntfyPort = 2586;
  ntfyTopic = "slskd-uploads";
  ntfyUrl = "http://${media.host}.ts.${config.fleet.identity.homelab.dns}:${toString ntfyPort}";
  notifyIdleSeconds = 45;
in {
  fleet.services.slskd = {
    host = media.host;
    description = "Soulseek client";
    path = "/slskd/";
    port = webPort;
    # slskd's own authentication is disabled, so the edge plus Authelia is the
    # only gate; its API clients need their credentials passed through untouched.
    auth = "backend";
    localProxy.port = webPort;
  };

  fleet.aspects = {
    slskd-notify-server.hosts = [media.host];
    slskd-notify-client.tags = ["desktop"];
  };

  flake.modules.nixos.slskd = {
    config,
    lib,
    pkgs,
    ...
  }: let
    collectLibrarySize = pkgs.writeShellApplication {
      name = "collect-slskd-library-size";
      runtimeInputs = [pkgs.coreutils];
      text = ''
        bytes="$(du --summarize --block-size=1 ${lib.escapeShellArg media.library} | cut --fields=1)"
        output="${nodeExporterTextfileDir}/slskd-library.prom"
        temporary="$(mktemp --tmpdir=${nodeExporterTextfileDir} .slskd-library.prom.XXXXXX)"

        printf '%s\n' \
          '# HELP slskd_library_bytes Disk space used by the shared Soulseek library.' \
          '# TYPE slskd_library_bytes gauge' \
          "slskd_library_bytes $bytes" \
          > "$temporary"
        chmod 0644 "$temporary"
        mv --force "$temporary" "$output"
      '';
    };
  in {
    users.users.slskd = {
      extraGroups = ["media"];
      home = "/var/lib/slskd";
    };

    systemd.services.collect-slskd-library-size = {
      description = "Export shared Soulseek library size for node_exporter";
      requisite = [config.mediaPool.mountUnit];
      after = [config.mediaPool.mountUnit];
      unitConfig.RequiresMountsFor = [media.library];
      serviceConfig = {
        Type = "oneshot";
        ExecStart = lib.getExe collectLibrarySize;
        DynamicUser = true;
        SupplementaryGroups = ["media" "node-exporter"];
        ReadWritePaths = [nodeExporterTextfileDir];
      };
    };

    systemd.timers.collect-slskd-library-size = {
      description = "Periodically measure the shared Soulseek library size";
      wantedBy = ["timers.target"];
      timerConfig = {
        OnBootSec = "5min";
        OnUnitActiveSec = "6h";
        RandomizedDelaySec = "10min";
        Persistent = true;
      };
    };

    systemd.tmpfiles.rules = [
      "d ${media.slskdDir} 2775 slskd media - -"
    ];

    age.secrets.slskd-environment.file = ../../../secrets/slskd-environment.age;

    systemd.services.slskd = {
      # Stop slskd if the removable media drive disappears and restart it when
      # the drive is connected again.
      wantedBy = [config.mediaPool.deviceUnit];
      after = [config.mediaPool.mountUnit];
      bindsTo = [config.mediaPool.mountUnit];
      unitConfig.RequiresMountsFor = [
        media.library
        media.downloads
        media.incomplete
      ];
      serviceConfig.UMask = "0002";
    };

    services.slskd = {
      enable = true;
      environmentFile = config.age.secrets.slskd-environment.path;
      openFirewall = true;
      settings = {
        directories = {
          downloads = media.downloads;
          incomplete = media.incomplete;
        };
        shares = {
          directories = ["[Music]${media.library}"];
          cache.retention = 60;
        };
        global = {
          upload = {
            slots = 5;
            speed_limit = 10240;
          };
          limits.queued = {
            files = 250;
            megabytes = 20480;
          };
        };
        soulseek.listen_port = listenPort;
        web = {
          ip_address = "127.0.0.1";
          port = webPort;
          url_base = service.basePath;
          # The edge is the only entry point and requires an Authelia session.
          authentication.disabled = true;
        };
      };
    };
  };

  flake.modules.nixos.slskd-notify-server = {
    lib,
    pkgs,
    ...
  }: let
    recordUploadMetric = pkgs.writeShellApplication {
      name = "slskd-record-upload-metric";
      runtimeInputs = with pkgs; [coreutils curl jq util-linux];
      text = ''
        bytes="''${1:-}"
        state="${notifySpoolDir}/upload-metrics.json"
        lock="${notifySpoolDir}/upload-metrics.lock"

        if [[ -n "$bytes" ]]; then
          [[ "$bytes" =~ ^[0-9]+$ ]]
        fi
        exec 9>"$lock"
        flock 9

        if [[ -s "$state" ]]; then
          current="$(cat "$state")"
        else
          current='{"files":0,"bytes":0}'
        fi

        if [[ -n "$bytes" ]]; then
          next="$(jq --argjson bytes "$bytes" \
            '.files = ((.files // 0) + 1) | .bytes = ((.bytes // 0) + $bytes)' \
            <<<"$current")"
        else
          next="$current"
        fi

        state_tmp="$(mktemp --tmpdir=${notifySpoolDir} .upload-metrics.json.XXXXXX)"
        printf '%s\n' "$next" > "$state_tmp"
        mv --force "$state_tmp" "$state"

        # Pushed straight into VictoriaMetrics so the event shows up on the
        # dashboard immediately, instead of waiting for the next scrape. A
        # transient failure here (e.g. VictoriaMetrics not reachable yet
        # during a rolling deploy) is logged but not fatal -- the local
        # upload-metrics.json state above is already durable, and the next
        # successful push carries the correct cumulative totals forward.
        if ! printf '%s\n' \
          "slskd_upload_files_total{host=\"${media.host}\"} $(jq --raw-output .files <<<"$next")" \
          "slskd_upload_bytes_total{host=\"${media.host}\"} $(jq --raw-output .bytes <<<"$next")" \
          | curl --silent --show-error --fail --max-time 5 \
              --data-binary @- \
              "${victoriaMetricsUrl}/api/v1/import/prometheus"
        then
          echo "warning: failed to push slskd upload metrics to VictoriaMetrics" >&2
        fi
      '';
    };

    uploadHook = pkgs.writeShellApplication {
      name = "slskd-upload-notify-hook";
      runtimeInputs = with pkgs; [coreutils jq util-linux];
      text = ''
        logger --tag slskd-upload-notify "received UploadFileComplete event"

        line="$(${lib.getExe pkgs.jq} -e -c '
          . as $event
          | ($event.transfer.filename // $event.remoteFilename // $event.localFilename)
          | gsub("\\\\"; "/")
          | split("/") as $parts
          | ($parts[-1] | sub("\\.[^.]+$"; "")) as $song
          | ($parts[0:-1]) as $dirs
          | ($dirs[-1] // "Unknown album") as $leaf
          | {
              user: $event.transfer.username,
              song: $song,
              album: (
                if ($leaf | test("^(cd|dis[ck])[ _-]?[0-9]+$"; "i"))
                then ($dirs[-2] // $leaf)
                else $leaf
                end
              ),
              bytes: ($event.transfer.bytesTransferred // $event.transfer.size)
            }
        ' <<<"$SLSKD_SCRIPT_DATA")"

        key="$(printf '%s\0%s' \
          "$(printf '%s' "$line" | jq -r .user)" \
          "$(printf '%s' "$line" | jq -r .album)" \
          | sha256sum | cut -c1-20)"
        printf '%s\n' "$line" >> "${notifySpoolDir}/$key.jsonl"
        logger --tag slskd-upload-notify -- "spooled $key: $(printf '%s' "$line" | jq -r '"\(.song) from \(.album) — \(.bytes) bytes to \(.user)"')"

        if ! ${lib.getExe recordUploadMetric} "$(printf '%s' "$line" | jq --raw-output .bytes)"; then
          logger --tag slskd-upload-notify --priority warning "failed to update upload metrics"
        fi
      '';
    };

    flushUploads = pkgs.writeShellApplication {
      name = "slskd-upload-notify-flush";
      runtimeInputs = with pkgs; [coreutils curl jq util-linux];
      text = ''
        cd ${notifySpoolDir}
        now="$(date +%s)"

        for file in *.jsonl; do
          [[ -e "$file" ]] || continue
          (( now - $(stat -c %Y "$file") >= ${toString notifyIdleSeconds} )) || continue

          sending="$file.sending"
          mv "$file" "$sending"
          logger --tag slskd-upload-notify -- "publishing batch $sending after ${toString notifyIdleSeconds}s idle"

          if jq -s --arg topic ${lib.escapeShellArg ntfyTopic} '
            def human_size:
              if . >= 1073741824 then
                "\((. / 107374182.4 | round) / 10) GiB"
              elif . >= 1048576 then
                "\((. / 104857.6 | round) / 10) MiB"
              elif . >= 1024 then
                "\((. / 102.4 | round) / 10) KiB"
              else
                "\(.) B"
              end;
            (map(.bytes) | add) as $bytes
            | {
                topic: $topic,
                title: (
                  if length == 1
                  then "Uploaded \(.[0].song)"
                  else "Uploaded \(.[0].album)"
                  end
                ),
                message: (
                  if length == 1
                  then "Album: \(.[0].album) • \($bytes | human_size) sent to \(.[0].user)"
                  else "\(length) files • \($bytes | human_size) sent to \(.[0].user)"
                  end
                ),
                tags: ["arrow_up", "musical_note"]
              }
          ' "$sending" \
            | curl --fail --silent --show-error \
                --header 'Content-Type: application/json' \
                --data-binary @- \
                ${lib.escapeShellArg ntfyUrl}
          then
            logger --tag slskd-upload-notify -- "published batch $sending"
            rm "$sending"
          else
            # Keep failed deliveries in the spool for the next timer tick.
            cat "$sending" >> "$file"
            rm "$sending"
            exit 1
          fi
        done
      '';
    };
  in {
    assertions = [
      {
        assertion = config.fleet.hosts.${media.host}.tailscale.enable;
        message = "slskd upload notifications require Tailscale on '${media.host}'.";
      }
    ];

    networking.firewall.interfaces.tailscale0.allowedTCPPorts = [ntfyPort];

    systemd.services.slskd.serviceConfig = {
      StateDirectory = [notifyStateDirectory];
    };

    # Re-pushes the current cumulative counts on a timer (with no new upload
    # to record) so the series in VictoriaMetrics never goes more than a few
    # minutes stale. Without this, an instant query run between uploads can
    # fall outside Prometheus/VictoriaMetrics' default lookback window and
    # come back empty, since a push only otherwise happens when a file
    # actually completes uploading.
    systemd.services.slskd-upload-metrics-heartbeat = {
      description = "Push current slskd upload metrics into VictoriaMetrics";
      wantedBy = ["multi-user.target"];
      wants = ["network-online.target"];
      after = ["systemd-tmpfiles-setup.service" "network-online.target"];
      serviceConfig = {
        Type = "oneshot";
        User = "slskd";
        Group = "slskd";
        StateDirectory = [notifyStateDirectory];
        ExecStart = lib.getExe recordUploadMetric;
      };
    };

    systemd.timers.slskd-upload-metrics-heartbeat = {
      description = "Periodically push current slskd upload metrics into VictoriaMetrics";
      wantedBy = ["timers.target"];
      timerConfig = {
        OnBootSec = "1min";
        OnUnitActiveSec = "3min";
        Persistent = true;
      };
    };

    services.slskd.settings.integration.scripts.upload-notify = {
      on = ["UploadFileComplete"];
      run.executable = lib.getExe uploadHook;
    };

    systemd.services.slskd-notify-flush = {
      description = "Publish completed slskd upload batches to ntfy";
      after = ["ntfy-sh.service"];
      wants = ["ntfy-sh.service"];
      serviceConfig = {
        Type = "oneshot";
        User = "slskd";
        Group = "slskd";
        ExecStart = lib.getExe flushUploads;
      };
    };

    systemd.timers.slskd-notify-flush = {
      description = "Periodically publish completed slskd upload batches";
      wantedBy = ["timers.target"];
      timerConfig = {
        OnBootSec = "1min";
        OnUnitActiveSec = "15s";
        AccuracySec = "1s";
        Persistent = true;
      };
    };

    services.ntfy-sh = {
      enable = true;
      settings = {
        base-url = ntfyUrl;
        listen-http = "0.0.0.0:${toString ntfyPort}";
        cache-file = "/var/lib/ntfy-sh/cache.db";
        cache-duration = "7d";
        web-root = "disable";
      };
    };
  };

  flake.modules.nixos.slskd-notify-client = {
    config,
    lib,
    pkgs,
    ...
  }: let
    desktopSubscriber = pkgs.writeShellApplication {
      name = "slskd-upload-notify-subscribe";
      runtimeInputs = [pkgs.libnotify];
      text = ''
        exec ${lib.getExe pkgs.python3} - ${lib.escapeShellArg "${ntfyUrl}/${ntfyTopic}/json"} <<'PY'
        import json
        import os
        import pathlib
        import subprocess
        import sys
        import time
        import urllib.error
        import urllib.parse
        import urllib.request

        endpoint = sys.argv[1]
        state_home = pathlib.Path(os.environ.get("XDG_STATE_HOME", pathlib.Path.home() / ".local/state"))
        state_dir = state_home / "slskd-notify"
        cursor_file = state_dir / "cursor"
        state_dir.mkdir(parents=True, exist_ok=True)

        while True:
            cursor = cursor_file.read_text().strip() if cursor_file.exists() else "all"
            url = endpoint + "?since=" + urllib.parse.quote(cursor)
            try:
                with urllib.request.urlopen(url, timeout=90) as response:
                    for raw_line in response:
                        event = json.loads(raw_line)
                        if event.get("event") != "message":
                            continue

                        subprocess.run(
                            [
                                "notify-send",
                                "--app-name=Soulseek",
                                "--icon=folder-music-symbolic",
                                event.get("title", "Soulseek upload"),
                                event.get("message", "Upload completed"),
                            ],
                            check=True,
                        )
                        cursor_file.write_text(event["id"] + "\n")
            except urllib.error.HTTPError as error:
                # A cursor older than ntfy's cache can no longer be resolved. In
                # that case, replay the remaining cache and establish a new one.
                if error.code == 400:
                    cursor_file.unlink(missing_ok=True)
                time.sleep(10)
            except (OSError, ValueError, json.JSONDecodeError):
                time.sleep(10)
        PY
      '';
    };
  in {
    assertions = [
      {
        assertion = config.services.displayManager.enable;
        message = "The slskd notification client needs a display manager.";
      }
    ];

    systemd.user.services.slskd-notify = {
      description = "Show slskd upload notifications from ${media.host}";
      wantedBy = ["graphical-session.target"];
      partOf = ["graphical-session.target"];
      after = ["graphical-session.target"];
      serviceConfig = {
        ExecStart = lib.getExe desktopSubscriber;
        Restart = "always";
        RestartSec = 10;
      };
    };
  };

  fleet.monitoring.panels.slskd = {
    title = "slskd uploads";
    description = "Completed uploads and the all-time uploaded share of the Soulseek library.";
    height = 8;
    order = 1;
    panel = let
      canvasText = {
        name,
        value,
        top,
        left,
        width,
        align ? "left",
      }: {
        inherit name;
        type = "text";
        config = {
          inherit align;
          valign = "middle";
          size = 20;
          text = {
            fixed = value;
            mode = "fixed";
          };
        };
        constraint = {
          horizontal = "left";
          vertical = "top";
        };
        placement = {
          inherit top left width;
          height = 38;
        };
      };
      canvasMetric = {
        name,
        field,
        top,
        left,
        width,
        align ? "right",
      }: {
        inherit name;
        type = "metric-value";
        config = {
          inherit align;
          valign = "middle";
          size = 20;
          text = {
            inherit field;
            fixed = "";
            mode = "field";
          };
        };
        constraint = {
          horizontal = "left";
          vertical = "top";
        };
        placement = {
          inherit top left width;
          height = 38;
        };
      };
      uploadRow = {
        prefix,
        bytesField,
        filesField,
        top,
      }: [
        (canvasText {
          name = "${prefix} label";
          value = "${prefix}:";
          inherit top;
          left = 20;
          width = 90;
          align = "right";
        })
        (canvasMetric {
          name = "${prefix} bytes";
          field = bytesField;
          inherit top;
          left = 120;
          width = 120;
        })
        (canvasText {
          name = "${prefix} opening parenthesis";
          value = "(";
          inherit top;
          left = 250;
          width = 10;
        })
        (canvasMetric {
          name = "${prefix} files";
          field = filesField;
          inherit top;
          left = 260;
          width = 50;
        })
        (canvasText {
          name = "${prefix} files suffix";
          value = " Files)";
          inherit top;
          left = 310;
          width = 65;
        })
      ];
    in {
      type = "canvas";
      datasource = {
        type = "prometheus";
        uid = "victoriametrics";
      };
      targets = [
        {
          refId = "A";
          expr = "increase(slskd_upload_files_total{host=\"${media.host}\"}[24h])";
          legendFormat = "24h files";
          instant = true;
        }
        {
          refId = "B";
          expr = "increase(slskd_upload_bytes_total{host=\"${media.host}\"}[24h])";
          legendFormat = "24h transferred";
          instant = true;
        }
        {
          refId = "C";
          expr = "increase(slskd_upload_files_total{host=\"${media.host}\"}[7d])";
          legendFormat = "7d files";
          instant = true;
        }
        {
          refId = "D";
          expr = "increase(slskd_upload_bytes_total{host=\"${media.host}\"}[7d])";
          legendFormat = "7d transferred";
          instant = true;
        }
        {
          # last_over_time rather than a bare instant selector, so this still
          # resolves if the dashboard is queried between upload events and the
          # heartbeat's last push happens to fall outside the default lookback.
          refId = "E";
          expr = "last_over_time(slskd_upload_files_total{host=\"${media.host}\"}[10m])";
          legendFormat = "All time files";
          instant = true;
        }
        {
          refId = "F";
          expr = "last_over_time(slskd_upload_bytes_total{host=\"${media.host}\"}[10m])";
          legendFormat = "All time transferred";
          instant = true;
        }
        {
          refId = "G";
          expr = "100 * last_over_time(slskd_upload_bytes_total{host=\"${media.host}\"}[10m]) / last_over_time(slskd_library_bytes{host=\"${media.host}\"}[10m])";
          legendFormat = "Share percentage";
          instant = true;
        }
      ];
      options = {
        inlineEditing = false;
        panZoom = false;
        showAdvancedTypes = false;
        zoomToContent = false;
        tooltip = {
          mode = "single";
          disableForOneClick = true;
        };
        root = {
          name = "Upload summary";
          type = "frame";
          elements =
            uploadRow {
              prefix = "24h";
              bytesField = "24h transferred";
              filesField = "24h files";
              top = 0;
            }
            ++ uploadRow {
              prefix = "7d";
              bytesField = "7d transferred";
              filesField = "7d files";
              top = 42;
            }
            ++ uploadRow {
              prefix = "all time";
              bytesField = "All time transferred";
              filesField = "All time files";
              top = 84;
            }
            ++ [
              (canvasText {
                name = "Share percentage label";
                value = "share percentage:";
                top = 134;
                left = 20;
                width = 180;
                align = "right";
              })
              (canvasMetric {
                name = "Share percentage";
                field = "Share percentage";
                top = 134;
                left = 210;
                width = 100;
                align = "left";
              })
            ];
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
          {
            matcher = {
              id = "byFrameRefID";
              options = "G";
            };
            properties = [
              {
                id = "unit";
                value = "percent";
              }
              {
                id = "decimals";
                value = 1;
              }
            ];
          }
        ];
      };
    };
  };

  fleet.monitoring.panels.slskd-upload-events = {
    title = "slskd upload events";
    description = "Outbound traffic on ${media.host}'s physical interface, with a vertical line at each completed slskd upload.";
    height = 8;
    order = 2;
    panel = {
      type = "timeseries";
      datasource = {
        type = "prometheus";
        uid = "victoriametrics";
      };
      targets = [
        {
          # Scraped continuously (unlike the event-driven slskd_upload_bytes_total
          # push), so the line keeps moving between uploads instead of going
          # stale. Excludes tailscale0 the same way the "Network traffic" panel
          # does, since slskd's Soulseek peers aren't reached over the tailnet.
          refId = "A";
          expr = "sum(rate(node_network_transmit_bytes_total{host=\"${media.host}\",device!~\"lo|tailscale0\"}[$__rate_interval]))";
          legendFormat = "${media.host} tx";
        }
      ];
      fieldConfig = {
        defaults = {
          unit = "Bps";
          min = 0;
        };
        overrides = [];
      };
    };
    annotations = [
      {
        datasource = {
          type = "prometheus";
          uid = "victoriametrics";
        };
        enable = true;
        iconColor = "orange";
        name = "slskd upload events";
        target = {
          expr = "changes(slskd_upload_files_total{host=\"${media.host}\"}[1m]) > 0";
          refId = "Anno";
        };
        titleFormat = "Upload completed";
      }
    ];
  };
}
