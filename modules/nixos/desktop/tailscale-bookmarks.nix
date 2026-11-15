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

  homelabBookmarks =
    config.network.hosts
    |> lib.mapAttrsToList (
      name: host:
        (host.publicWebServices
          |> lib.filterAttrs (_: service: service.bookmark)
          |> lib.mapAttrsToList (
            _: service:
              lib.nameValuePair service.title "https://${lib.optionalString (service.subdomain != null) "${service.subdomain}."}${config.identity.homelab.dns}${service.path}"
          ))
        ++ lib.optionals host.tailscale.enable (
          host.privateWebServices
          |> lib.filterAttrs (_: service: service.bookmark)
          |> lib.mapAttrsToList (
            _: service:
              lib.nameValuePair service.title "${service.scheme}://${name}.${tailnetDomain}:${toString service.port}${service.path}"
          )
        )
    )
    |> lib.concatLists
    |> builtins.listToAttrs;
in {
  home-manager.sharedModules = lib.optional self.tailscale.enable {
    gtk.gtk3.bookmarks = lib.mapAttrsToList bookmarkFor otherHosts;
    programs.ssh.matchBlocks = lib.mapAttrs sshMatchBlockFor otherHosts;
  };

  home-manager.users.${config.identity.user.name} = {config, ...}: {
    identity.firefox.homelabBookmarks = lib.mkIf (config.programs.firefox.enable && self.tailscale.enable) homelabBookmarks;
  };
}
