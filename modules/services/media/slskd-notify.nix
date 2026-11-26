# Desktop notifications for completed slskd uploads.
#
# Which machine runs the ntfy server is not configured anywhere here: it is read
# off the service registry, so moving slskd to another host moves the publisher
# with it and re-points every subscriber. The two halves are separate aspects
# enrolled by `hosts`/`tags`, which is why neither module contains any
# "am I the right host?" guard -- it is only ever evaluated where it belongs.
{
  config,
  lib,
  ...
}: let
  serverHost = config.fleet.services.slskd.host;
  textfileDir = config.fleet.monitoring.textfileDir;

  stateDirectory = "slskd-notify";
  spoolDir = "/var/lib/${stateDirectory}";
  ntfyPort = 2586;
  ntfyTopic = "slskd-uploads";
  ntfyUrl = "http://${serverHost}.ts.${config.fleet.identity.homelab.dns}:${toString ntfyPort}";
  idleSeconds = 45;
in {
  fleet.aspects = {
    slskd-notify-server.hosts = [serverHost];
    slskd-notify-client.tags = ["desktop"];
  };

  flake.modules.nixos.slskd-notify-server = {pkgs, ...}: let
    recordUploadMetric = pkgs.writeShellApplication {
      name = "slskd-record-upload-metric";
      runtimeInputs = with pkgs; [coreutils jq util-linux];
      text = ''
        bytes="''${1:-}"
        state="${spoolDir}/upload-metrics.json"
        lock="${spoolDir}/upload-metrics.lock"
        output="${textfileDir}/slskd.prom"

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

        state_tmp="$(mktemp --tmpdir=${spoolDir} .upload-metrics.json.XXXXXX)"
        printf '%s\n' "$next" > "$state_tmp"
        mv --force "$state_tmp" "$state"

        metrics_tmp="$(mktemp --tmpdir=${textfileDir} .slskd.prom.XXXXXX)"
        printf '%s\n' \
          '# HELP slskd_upload_files_total Number of completed slskd uploads.' \
          '# TYPE slskd_upload_files_total counter' \
          "slskd_upload_files_total $(jq --raw-output .files <<<"$next")" \
          '# HELP slskd_upload_bytes_total Bytes sent by completed slskd uploads.' \
          '# TYPE slskd_upload_bytes_total counter' \
          "slskd_upload_bytes_total $(jq --raw-output .bytes <<<"$next")" \
          > "$metrics_tmp"
        chmod 0644 "$metrics_tmp"
        mv --force "$metrics_tmp" "$output"
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
        printf '%s\n' "$line" >> "${spoolDir}/$key.jsonl"
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
        cd ${spoolDir}
        now="$(date +%s)"

        for file in *.jsonl; do
          [[ -e "$file" ]] || continue
          (( now - $(stat -c %Y "$file") >= ${toString idleSeconds} )) || continue

          sending="$file.sending"
          mv "$file" "$sending"
          logger --tag slskd-upload-notify -- "publishing batch $sending after ${toString idleSeconds}s idle"

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
        assertion = config.fleet.hosts.${serverHost}.tailscale.enable;
        message = "slskd upload notifications require Tailscale on '${serverHost}'.";
      }
    ];

    networking.firewall.interfaces.tailscale0.allowedTCPPorts = [ntfyPort];

    systemd.services.slskd.serviceConfig = {
      StateDirectory = [stateDirectory];
      ReadWritePaths = [textfileDir];
    };
    users.users.slskd.extraGroups = ["node-exporter"];

    systemd.services.slskd-upload-metrics-init = {
      description = "Initialize slskd upload metrics for node_exporter";
      wantedBy = ["multi-user.target"];
      after = ["systemd-tmpfiles-setup.service"];
      serviceConfig = {
        Type = "oneshot";
        User = "slskd";
        Group = "slskd";
        StateDirectory = [stateDirectory];
        ExecStart = lib.getExe recordUploadMetric;
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
      description = "Show slskd upload notifications from ${serverHost}";
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
}
