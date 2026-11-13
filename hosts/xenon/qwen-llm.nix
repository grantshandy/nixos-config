{pkgs, ...}: {
  services.ollama = {
    enable = true;
    package = pkgs.ollama-rocm;

    # The RX 6600 is gfx1032, which ROCm can run using its supported gfx1030 target.
    rocmOverrideGfx = "10.3.0";

    # Listen on the tailnet without opening the port on other interfaces.
    # tailscale0 is already trusted by modules/nixos/network-base.nix.
    host = "0.0.0.0";
    openFirewall = false;

    loadModels = ["qwen3.5:9b-q4_K_M"];

    environmentVariables = {
      # Leave enough of the RX 6600's 8 GiB VRAM for the context and vision projector.
      OLLAMA_CONTEXT_LENGTH = "8192";
      OLLAMA_FLASH_ATTENTION = "1";
      OLLAMA_KV_CACHE_TYPE = "q8_0";
      OLLAMA_MAX_LOADED_MODELS = "1";
      OLLAMA_NUM_PARALLEL = "1";
      OLLAMA_KEEP_ALIVE = "30m";
    };
  };
}
