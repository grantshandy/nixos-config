# The edge. Terminates TLS, authorizes every public request, and serves tailnet
# DNS -- which is why it deploys last.
let
  extraStorageRoot = "/mnt/extra-usb";
in {
  fleet.hosts.krypton = {
    system = "x86_64-linux";
    tags = ["edge" "tailnet-dns" "lean"];
    homeManager.enable = false;
    remoteDevelopment.enable = false;

    ssh = {
      enable = true;
      port = 22;
    };
    tailscale = {
      enable = true;
      ipv4 = "100.64.0.3";
    };

    buildCluster.builders.use = {
      enable = true;
      providers = ["radon"];
      localJobs = 0;
    };

    inherit extraStorageRoot;
  };

  flake.modules.nixos.krypton = {modulesPath, ...}: {
    imports = [
      (modulesPath + "/profiles/minimal.nix")
      (import ./_hardware/krypton.nix {inherit extraStorageRoot;})
    ];

    networking.useDHCP = true;

    nix = {
      gc = {
        automatic = true;
        dates = "weekly";
        options = "--delete-older-than 7d";
      };
      settings = {
        min-free = 1024 * 1024 * 1024;
        max-free = 2 * 1024 * 1024 * 1024;
      };
    };

    services.openssh.settings.PasswordAuthentication = false;

    # The base user has no declarative password. Keep the key-authenticated user
    # capable of administering this headless machine after its first boot.
    security.sudo.wheelNeedsPassword = false;
  };
}
