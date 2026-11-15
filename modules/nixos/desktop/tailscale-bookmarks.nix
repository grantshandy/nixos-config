{
  config,
  lib,
  ...
}: let
  thisHost = config.networking.hostName;
  self = config.network.hosts.${thisHost};
  tailnetDomain = "ts.${config.identity.homelab.dns}";
  otherHosts =
    lib.filterAttrs
    (name: h: name != thisHost && h.ssh.enable && h.tailscale.enable)
    config.network.hosts;

  bookmarkFor = name: h: "sftp://${name}:${toString h.ssh.port}/home/${config.identity.user.name}/ ${name}";

  sshMatchBlockFor = name: h: {
    hostname = "${name}.${tailnetDomain}";
    port = h.ssh.port;
  };

  homelabBookmarks = builtins.listToAttrs (lib.concatLists (lib.mapAttrsToList (
      name: host:
        lib.mapAttrsToList (
          _: service:
            lib.nameValuePair service.title "https://${lib.optionalString (service.subdomain != null) "${service.subdomain}."}${config.identity.homelab.dns}${service.path}"
        ) (lib.filterAttrs (_: service: service.bookmark) host.publicWebServices)
        ++ lib.optionals host.tailscale.enable (lib.mapAttrsToList (
          _: service:
            lib.nameValuePair service.title "${service.scheme}://${name}.${tailnetDomain}:${toString service.port}${service.path}"
        ) (lib.filterAttrs (_: service: service.bookmark) host.privateWebServices))
    )
    config.network.hosts));
in {
  home-manager.sharedModules =
    lib.optional self.firefox.enable ../../home/firefox
    ++ lib.optional self.tailscale.enable {
      gtk.gtk3.bookmarks = lib.mapAttrsToList bookmarkFor otherHosts;
      programs.ssh.matchBlocks = lib.mapAttrs sshMatchBlockFor otherHosts;
    };

  home-manager.users.${config.identity.user.name} = lib.mkIf (self.firefox.enable && self.tailscale.enable) {
    identity.firefox.homelabBookmarks = homelabBookmarks;
  };
}
