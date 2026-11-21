{
  config,
  lib,
  pkgs,
  ...
}: let
  webui = config.network.hosts.xenon.publicWebServices.OpenWebUI;
  webuiHost = "${webui.subdomain}.${config.identity.homelab.dns}";

  contextLength = 16384;
  modelName = "qwen3.6-35b-a3b-q4-k-m";
  model = pkgs.fetchurl {
    url = "https://huggingface.co/unsloth/Qwen3.6-35B-A3B-GGUF/resolve/main/Qwen3.6-35B-A3B-UD-Q4_K_M.gguf";
    hash = "sha256-rA4sEYngVfqjbv82FYDnnFvW+Odr/7TOVH8WfVPjGmE=";
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
    inherit model;
    host = "0.0.0.0";
    port = 8081;
    openFirewall = false;
    extraFlags = [
      "--alias"
      modelName
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

  # The RX 6600 is gfx1032, which ROCm can run using its supported gfx1030 target.
  systemd.services.llama-cpp.serviceConfig = {
    Environment = ["HSA_OVERRIDE_GFX_VERSION=10.3.0"];
    SupplementaryGroups = ["render" "video"];
    DevicePolicy = lib.mkForce "auto";
    DeviceAllow = lib.mkForce [];
  };
}
