{
  identity = {
    homelab.dns = "example.duckdns.org";
    user = {
      name = "alice";
      description = "Alice Example";
    };

    ssh = {
      userKeys = [
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIReplaceWithYourPublicKey alice@example"
      ];
      hostKeys = {
        krypton = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIReplaceWithKryptonsPublicHostKey root@krypton";
        radon = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIReplaceWithRadonsPublicHostKey root@radon";
        xenon = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIReplaceWithXenonsPublicHostKey root@xenon";
        neon = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIReplaceWithNeonsPublicHostKey root@neon";
      };
    };

    git = {
      name = "alice";
      email = "alice@example.com";
    };

    firefox = {
      defaultEngine = "ddg";
      extensions = [
        "ublock-origin"
        "darkreader"
      ];
      bookmarks."NixOS Wiki" = "https://wiki.nixos.org/wiki/NixOS_Wiki";
      searchEngines = {
        homemanager = "https://home-manager-options.extranix.com/?query={s}&release=master";
      };
    };
  };
}
