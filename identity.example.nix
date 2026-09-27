{
  # This file contains evaluation-time preferences, not secrets. Copy the
  # settings you want into identity.nix and keep credentials in secrets/.
  identity = {
    homelab.dns = "example.duckdns.org";
    stateVersion = "26.05";

    user = {
      name = "alice";
      description = "Alice Example";
      sshKeys = [
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIReplaceWithYourPublicKey alice@example"
      ];
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
      bookmarks = [
        {
          name = "NixOS Wiki";
          url = "https://wiki.nixos.org/wiki/NixOS_Wiki";
        }
      ];
      searchEngines = {
        homemanager = "https://home-manager-options.extranix.com/?query={s}&release=master";
      };
    };
  };
}
