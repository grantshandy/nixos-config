# Laptop. Builds aarch64 locally via binfmt and offloads heavy jobs to xenon.
{
  fleet.hosts.helium = {
    system = "x86_64-linux";
    tags = ["desktop"];

    ssh = {
      enable = true;
      port = 4321;
    };
    tailscale.enable = true;

    buildCluster = {
      cache.provide = {
        enable = true;
        priority = 30;
      };
      builders.use = {
        enable = true;
        providers = ["xenon"];
        localJobs = 1;
      };
    };
  };

  flake.modules.nixos.helium = {
    imports = [./_hardware/helium.nix];

    boot.binfmt.emulatedSystems = ["aarch64-linux"];
  };
}
