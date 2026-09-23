{
  config,
  lib,
  ...
}: let
  thisHost = config.networking.hostName;
  tailnetDomain = "ts.${config.identity.homelab.dns}";
  otherHosts =
    lib.filterAttrs
    (name: h: name != thisHost && h.ssh.enable && h.tailscale.enable)
    config.network.hosts;
  bookmarkFor = name: h: "sftp://${name}.${tailnetDomain}:${toString h.ssh.port}/home/${config.identity.user.name}/ ${name}";
in {
  home-manager.sharedModules = [
    {gtk.gtk3.bookmarks = lib.mapAttrsToList bookmarkFor otherHosts;}
  ];
}
