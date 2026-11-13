{
  config,
  lib,
  ...
}: let
  self = config.network.hosts.${config.networking.hostName};
  homelabBookmarks = builtins.listToAttrs (
    lib.concatMap (
      host:
        lib.mapAttrsToList (
          _: service:
            lib.nameValuePair service.title "https://${lib.optionalString (service.subdomain != null) "${service.subdomain}."}${config.identity.homelab.dns}${service.path}"
        )
        host.webServices
    ) (lib.attrValues config.network.hosts)
  );
in
  lib.mkIf self.firefox.enable {
    home-manager.sharedModules = [../home/firefox];
    home-manager.users.${config.identity.user.name}.identity.firefox.homelabBookmarks = homelabBookmarks;
  }
