# llama.cpp behind Open WebUI, plus its tailnet-only editor API.
{
  config,
  lib,
  ...
}: let
  fleet = config.fleet;

  llmHosts =
    fleet.hosts
    |> lib.filterAttrs (_: host: lib.elem "llm" host.tags)
    |> lib.attrNames;

  llmHost =
    if lib.length llmHosts == 1
    then lib.head llmHosts
    else throw "Exactly one host must be tagged \"llm\", found: ${lib.concatStringsSep ", " llmHosts}.";

  model = {
    name = "qwen3.6-35b-a3b-q4-k-m";
    displayName = "Qwen 3.6 35B A3B Q4_K_M";
    contextLength = 65536;
    maxOutputTokens = 32768;
    fileName = "Qwen3.6-35B-A3B-UD-Q4_K_M.gguf";
    url = "https://huggingface.co/unsloth/Qwen3.6-35B-A3B-GGUF/resolve/main/${model.fileName}";
    sha256 = "ac0e2c1189e055faa36eff361580e79c5bd6f8e76bffb4ce547f167d53e31a61";
  };

  llama = config.fleet.services.LlamaCpp;
in {
  fleet.services.OpenWebUI = {
    host = llmHost;
    title = "Open WebUI";
    description = "Local AI chat and coding assistant";
    subdomain = "chat";
    port = 8080;
    auth = "session";
    upstream = "direct";
  };

  fleet.services.LlamaCpp = {
    host = llmHost;
    port = 8081;
    public = false;
  };

  fleet.aspects.local-llm.tags = ["llm"];

  flake.modules.nixos.local-llm =
    ({
      webui,
      nodeExporterTextfileDir,
    }: {
      config,
      lib,
      pkgs,
      ...
    }: let
      idleTimeoutSeconds = 15 * 60;
      modelDirectory = "/var/lib/llama-models";
      modelPath = "${modelDirectory}/${model.fileName}";

      provisionModel = pkgs.writeShellApplication {
        name = "provision-llama-model";
        runtimeInputs = [pkgs.coreutils pkgs.curl];
        text = ''
          destination=${lib.escapeShellArg modelPath}
          partial="${lib.escapeShellArg modelPath}.part"
          expected_hash=${lib.escapeShellArg model.sha256}

          if [ -f "$destination" ] && printf '%s  %s\n' "$expected_hash" "$destination" | sha256sum --check --status; then
            exit 0
          fi

          rm -f "$destination"
          curl \
            --fail \
            --location \
            --retry 5 \
            --retry-all-errors \
            --continue-at - \
            --output "$partial" \
            ${lib.escapeShellArg model.url}

          printf '%s  %s\n' "$expected_hash" "$partial" | sha256sum --check --status
          chmod 0644 "$partial"
          mv -f "$partial" "$destination"
        '';
      };

      llmMetrics = pkgs.writeShellApplication {
        name = "llama-cpp-metrics";
        runtimeInputs = with pkgs; [coreutils curl gawk jq];
        text = ''
          metrics_url="http://127.0.0.1:${toString config.services.llama-cpp.port}/models"
          output="${nodeExporterTextfileDir}/llama-cpp.prom"
          interval=2

          active=0
          started=0
          finished=0

          if [[ -r "$output" ]]; then
            started="$(awk '$1 == "llama_cpp_last_started_timestamp_seconds" { print $2 }' "$output")"
            finished="$(awk '$1 == "llama_cpp_last_finished_timestamp_seconds" { print $2 }' "$output")"
          fi
          [[ "$started" =~ ^[0-9]+$ ]] || started=0
          [[ "$finished" =~ ^[0-9]+$ ]] || finished=0

          sample_active() {
            local body
            if ! body="$(curl --silent --fail --max-time 2 "$metrics_url")"; then
              echo 0
              return
            fi
            # Active when any model is resident or loading, i.e. not sleeping/unloaded.
            if jq -e '[.data[]? | .status.value // "unknown"] | any(. != "sleeping" and . != "unloaded")' <<<"$body" >/dev/null 2>&1; then
              echo 1
            else
              echo 0
            fi
          }

          sample_gpu() {
            local dev
            gpu_busy=0
            vram_used=0
            vram_total=0
            for dev in /sys/class/drm/card*/device; do
              if [[ -r "$dev/gpu_busy_percent" && -r "$dev/mem_info_vram_used" && -r "$dev/mem_info_vram_total" ]]; then
                gpu_busy="$(cat "$dev/gpu_busy_percent" 2>/dev/null || echo 0)"
                vram_used="$(cat "$dev/mem_info_vram_used" 2>/dev/null || echo 0)"
                vram_total="$(cat "$dev/mem_info_vram_total" 2>/dev/null || echo 0)"
                break
              fi
            done
          }

          write_metrics() {
            local temporary
            temporary="$(mktemp --tmpdir="${nodeExporterTextfileDir}" .llama-cpp.prom.XXXXXX)"
            {
              printf '%s\n' \
                '# HELP llama_cpp_active Whether llama-cpp model is active/loaded (1) or idle/unloaded (0).' \
                '# TYPE llama_cpp_active gauge' \
                "llama_cpp_active $active" \
                '# HELP llama_cpp_last_started_timestamp_seconds Unix timestamp when llama-cpp model was last activated.' \
                '# TYPE llama_cpp_last_started_timestamp_seconds gauge' \
                "llama_cpp_last_started_timestamp_seconds $started" \
                '# HELP llama_cpp_last_finished_timestamp_seconds Unix timestamp when llama-cpp model was last deactivated.' \
                '# TYPE llama_cpp_last_finished_timestamp_seconds gauge' \
                "llama_cpp_last_finished_timestamp_seconds $finished" \
                '# HELP llama_cpp_info Local LLM model information; gauge value is 1 when active, 0 when inactive.' \
                '# TYPE llama_cpp_info gauge' \
                "llama_cpp_info{model=\"${model.name}\"} $active" \
                '# HELP amdgpu_gpu_busy_percent AMD GPU busy percentage (0-100).' \
                '# TYPE amdgpu_gpu_busy_percent gauge' \
                "amdgpu_gpu_busy_percent $gpu_busy" \
                '# HELP amdgpu_vram_used_bytes AMD GPU VRAM used in bytes.' \
                '# TYPE amdgpu_vram_used_bytes gauge' \
                "amdgpu_vram_used_bytes $vram_used" \
                '# HELP amdgpu_vram_total_bytes AMD GPU VRAM total in bytes.' \
                '# TYPE amdgpu_vram_total_bytes gauge' \
                "amdgpu_vram_total_bytes $vram_total"
            } > "$temporary"
            chmod 0644 "$temporary"
            mv --force "$temporary" "$output"
          }

          mark_idle() {
            active=0
            gpu_busy=0
            vram_used=0
            vram_total=0
            write_metrics
          }
          trap mark_idle EXIT
          trap 'exit 0' INT TERM

          gpu_busy=0
          vram_used=0
          vram_total=0

          active="$(sample_active)"
          sample_gpu
          write_metrics

          while true; do
            sleep "$interval"
            current="$(sample_active)"
            sample_gpu
            now="$(date +%s)"

            if [[ "$current" != "$active" ]]; then
              if [[ "$current" == 1 ]]; then
                started="$now"
                echo "llama-cpp activated at $now"
              else
                finished="$now"
                echo "llama-cpp deactivated at $now"
              fi
              active="$current"
            fi

            write_metrics
          done
        '';
      };
    in {
      services.open-webui = {
        enable = true;
        host = "0.0.0.0";
        port = webui.port;
        openFirewall = false;
        environment = {
          ENABLE_OLLAMA_API = "False";
          ENABLE_OPENAI_API = "True";
          OPENAI_API_BASE_URLS = "http://127.0.0.1:${toString config.services.llama-cpp.port}/v1";
          OPENAI_API_KEYS = "none";
          WEBUI_URL = webui.url;
          # No-login mode shares one account with everyone who can reach the UI.
          WEBUI_AUTH = "False";
          ENABLE_PERSISTENT_CONFIG = "False";
          DEFAULT_MODELS = model.name;
          ENABLE_TITLE_GENERATION = "False";
          ENABLE_TAGS_GENERATION = "False";
          ENABLE_FOLLOW_UP_GENERATION = "False";
          SCARF_NO_ANALYTICS = "True";
          DO_NOT_TRACK = "True";
          ANONYMIZED_TELEMETRY = "False";
        };
      };

      networking.firewall.interfaces.tailscale0.allowedTCPPorts = [
        webui.port
        config.services.llama-cpp.port
      ];
      systemd.services.open-webui = {
        wants = ["llama-cpp.service"];
        after = ["llama-cpp.service"];
      };

      services.llama-cpp = {
        enable = true;
        package = pkgs.llama-cpp-rocm;
        modelsPreset.${model.name} = {
          model = modelPath;
          load-on-startup = false;
        };
        host = "0.0.0.0";
        port = llama.port;
        openFirewall = false;
        extraFlags = [
          "--no-mmproj"
          "--n-gpu-layers"
          "99"
          "--n-cpu-moe"
          "31"
          # Prevent llama.cpp's automatic fitter from silently overriding the
          # benchmarked CPU/GPU tensor placement.
          "--fit"
          "off"
          "--ctx-size"
          (toString model.contextLength)
          # Unload the model and KV cache after being idle; the next request reloads them.
          "--sleep-idle-seconds"
          (toString idleTimeoutSeconds)
          "--flash-attn"
          "on"
          "--cache-type-k"
          "q8_0"
          "--cache-type-v"
          "q8_0"
          "--threads"
          "10"
          "--threads-batch"
          "16"
          "--parallel"
          "1"
          "--n-predict"
          (toString model.maxOutputTokens)
          "--reasoning"
          "off"
          "--cache-ram"
          "0"
          "--jinja"
        ];
      };

      systemd.services.llama-model-provision = {
        description = "Provision the llama.cpp model outside the Nix store";
        wants = ["network-online.target"];
        after = ["network-online.target"];
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          StateDirectory = "llama-models";
          StateDirectoryMode = "0755";
          ExecStart = lib.getExe provisionModel;
        };
      };

      # Do not start the API with a missing or unverified model. The provisioning
      # unit becomes a no-op once the persistent file passes its pinned checksum.
      systemd.services.llama-cpp = {
        requires = ["llama-model-provision.service"];
        after = ["llama-model-provision.service"];

        # The RX 6600 is gfx1032, which ROCm can run using its supported gfx1030 target.
        serviceConfig = {
          Environment = ["HSA_OVERRIDE_GFX_VERSION=10.3.0"];
          SupplementaryGroups = ["render" "video"];
          DevicePolicy = lib.mkForce "auto";
          DeviceAllow = lib.mkForce [];
        };
      };

      systemd.services.llama-cpp-metrics = {
        description = "Export llama-cpp activity and GPU metrics for node_exporter";
        wantedBy = ["multi-user.target"];
        after = ["systemd-tmpfiles-setup.service"];
        serviceConfig = {
          ExecStart = lib.getExe llmMetrics;
          DynamicUser = true;
          SupplementaryGroups = ["node-exporter" "video" "render"];
          ReadWritePaths = [nodeExporterTextfileDir];
          Restart = "always";
          RestartSec = "2s";
        };
      };
    }) {
      webui = config.fleet.services.OpenWebUI;
      nodeExporterTextfileDir = config.fleet.monitoring.textfileDir;
    };

  flake.modules.homeManager.zed = {
    config,
    lib,
    osConfig,
    ...
  }: let
    host = fleet.hosts.${osConfig.networking.hostName};
  in {
    programs.zed-editor.userSettings = lib.mkIf (host.tailscale.enable && config.programs.zed-editor.enable) {
      language_models."llama.cpp" = {
        api_url = llama.tailnetUrl;
        auto_discover = false;
        available_models = [
          {
            name = model.name;
            display_name = model.displayName;
            max_tokens = model.contextLength;
            max_output_tokens = model.maxOutputTokens;
            supports_tools = true;
            supports_images = false;
            supports_thinking = true;
          }
        ];
      };

      agent = {
        default_model = {
          provider = "llama.cpp";
          model = model.name;
        };
        auto_compact = {
          enabled = true;
          threshold = "90%";
        };
      };
    };
  };

  fleet.monitoring.panels.local-llm = {
    title = "Xenon load during local LLM activity";
    description = "Xenon CPU, memory, GPU utilization, and GPU VRAM usage. Shaded regions mark when llama-cpp was active.";
    height = 9;
    order = 4;
    panel = {
      type = "timeseries";
      interval = "5s";
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
          custom.spanNulls = true;
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
    };
  };
}
