{
  config,
  lib,
  pkgs,
  ...
}: let
  webui = config.network.hosts.xenon.privateWebServices.OpenWebUI;
in {
  services.open-webui = {
    enable = true;
    host = "0.0.0.0";
    port = webui.port;
    openFirewall = false;
    environment = {
      OLLAMA_BASE_URL = "http://127.0.0.1:${toString config.services.ollama.port}";
      WEBUI_URL = "${webui.scheme}://xenon.ts.${config.identity.homelab.dns}:${toString webui.port}${webui.path}";
      # No-login mode shares one account with everyone who can reach the UI.
      WEBUI_AUTH = "False";
      ENABLE_PERSISTENT_CONFIG = "False";
      DEFAULT_MODELS = "qwen3.5:9b-q4_K_M";
      DEFAULT_MODEL_PARAMS = builtins.toJSON {
        num_ctx = 49152;
        keep_alive = "30m";
      };
      ENABLE_TITLE_GENERATION = "False";
      ENABLE_TAGS_GENERATION = "False";
      ENABLE_FOLLOW_UP_GENERATION = "False";
      SCARF_NO_ANALYTICS = "True";
      DO_NOT_TRACK = "True";
      ANONYMIZED_TELEMETRY = "False";
    };
  };

  networking.firewall.interfaces.tailscale0.allowedTCPPorts = [webui.port];
  systemd.services.open-webui = {
    wants = ["ollama.service"];
    after = ["ollama.service"];
  };

  # With DeviceAllow entries, even "auto" installs a restrictive device filter.
  # Clear both so ROCm can discover the GPU; Unix permissions and the render
  # supplementary group still control access to the devices.
  systemd.services.ollama.serviceConfig = {
    DevicePolicy = lib.mkForce "auto";
    DeviceAllow = lib.mkForce [];
  };

  services.ollama = {
    enable = true;
    package = pkgs.ollama-rocm;

    # The RX 6600 is gfx1032, which ROCm can run using its supported gfx1030 target.
    rocmOverrideGfx = "10.3.0";

    host = "0.0.0.0";
    openFirewall = true;

    loadModels = ["qwen3.5:9b-q4_K_M"];
    environmentVariables = {
      OLLAMA_CONTEXT_LENGTH = "49152";
      OLLAMA_FLASH_ATTENTION = "1";
      OLLAMA_KV_CACHE_TYPE = "q8_0";
      OLLAMA_MAX_LOADED_MODELS = "1";
      OLLAMA_NUM_PARALLEL = "1";
      OLLAMA_KEEP_ALIVE = "30m";
    };
  };
}
