{
  lib,
  pkgs,
  ...
}: {
  # The module's closed cgroup device policy prevents ROCm 7.2 from discovering
  # this GPU despite its generic DRM/KFD allow rules. Unix permissions and the
  # render supplementary group still restrict device access.
  systemd.services.ollama.serviceConfig.DevicePolicy = lib.mkForce "auto";

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
