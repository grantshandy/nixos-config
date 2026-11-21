{
  config,
  lib,
  pkgs,
  ...
}: let
  webui = config.network.hosts.xenon.publicWebServices.OpenWebUI;
  webuiHost = "${webui.subdomain}.${config.identity.homelab.dns}";

  contextLength = 16384;
  idleTimeoutSeconds = 15 * 60;
  modelName = "qwen3.6-35b-a3b-q4-k-m";
  modelFileName = "Qwen3.6-35B-A3B-UD-Q4_K_M.gguf";
  modelDirectory = "/var/lib/llama-models";
  modelPath = "${modelDirectory}/${modelFileName}";
  modelUrl = "https://huggingface.co/unsloth/Qwen3.6-35B-A3B-GGUF/resolve/main/${modelFileName}";
  modelSha256 = "ac0e2c1189e055faa36eff361580e79c5bd6f8e76bffb4ce547f167d53e31a61";

  provisionModel = pkgs.writeShellApplication {
    name = "provision-llama-model";
    runtimeInputs = [pkgs.coreutils pkgs.curl];
    text = ''
      destination=${lib.escapeShellArg modelPath}
      partial="${lib.escapeShellArg modelPath}.part"
      expected_hash=${lib.escapeShellArg modelSha256}

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
        ${lib.escapeShellArg modelUrl}

      printf '%s  %s\n' "$expected_hash" "$partial" | sha256sum --check --status
      chmod 0644 "$partial"
      mv -f "$partial" "$destination"
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
      WEBUI_URL = "https://${webuiHost}${webui.path}";
      # No-login mode shares one account with everyone who can reach the UI.
      WEBUI_AUTH = "False";
      ENABLE_PERSISTENT_CONFIG = "False";
      DEFAULT_MODELS = modelName;
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
    modelsPreset.${modelName} = {
      model = modelPath;
      load-on-startup = false;
    };
    host = "0.0.0.0";
    port = 8081;
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
      (toString contextLength)
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
      "1024"
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
}
