{
  config,
  lib,
  pkgs,
  ...
}: let
  thisHostName = config.networking.hostName;
  thisHost =
    config.network.hosts.${thisHostName}
    or (throw "host '${thisHostName}' is missing from network.hosts");
  serverHosts = lib.filterAttrs (_: host: host.publicWebServices ? slskd) config.network.hosts;
  serverHostNames = lib.attrNames serverHosts;
  serverHostName =
    if lib.length serverHostNames == 1
    then lib.head serverHostNames
    else throw "exactly one network host must advertise the slskd web service";
  serverEnabled = config.services.slskd.enable;
  clientEnabled = thisHost.tailscale.enable && config.services.displayManager.enable;

  stateDirectory = "slskd-notify";
  spoolDir = "/var/lib/${stateDirectory}";
  ntfyPort = 2586;
  ntfyTopic = "slskd-uploads";
  ntfyUrl = "http://${serverHostName}.ts.${config.identity.homelab.dns}:${toString ntfyPort}";
  idleSeconds = 45;

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
  config = lib.mkMerge [
    {
      assertions = [
        {
          assertion = !serverEnabled || thisHost.tailscale.enable;
          message = "slskd upload notifications require Tailscale on the slskd server";
        }
        {
          assertion = !serverEnabled || thisHostName == serverHostName;
          message = "the host running slskd must advertise it in network.hosts.<name>.publicWebServices";
        }
      ];
    }

    (lib.mkIf serverEnabled {
      networking.firewall.interfaces.tailscale0.allowedTCPPorts = [ntfyPort];

      systemd.services.slskd.serviceConfig.StateDirectory = [stateDirectory];

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
    })

    (lib.mkIf clientEnabled {
      systemd.user.services.slskd-notify = {
        description = "Show slskd upload notifications from ${serverHostName}";
        wantedBy = ["graphical-session.target"];
        partOf = ["graphical-session.target"];
        after = ["graphical-session.target"];
        serviceConfig = {
          ExecStart = lib.getExe desktopSubscriber;
          Restart = "always";
          RestartSec = 10;
        };
      };
    })
  ];
}
