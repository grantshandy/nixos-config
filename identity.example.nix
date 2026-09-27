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
      hostKeys.radon = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIReplaceWithRadonsPublicHostKey root@radon";
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
