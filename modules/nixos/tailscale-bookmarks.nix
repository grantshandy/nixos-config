{
  config,
  lib,
  pkgs,
  pkgs-unstable,
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
    user = config.identity.user.name;
  };

  zed = pkgs-unstable.zed-editor;
  accessible = self.ssh.enable && self.tailscale.enable;

  waypipeFor = name: h:
    pkgs.writeShellApplication {
      name = "waypipe-${name}";
      runtimeInputs = [pkgs.waypipe pkgs.openssh];
      text = ''
        if [ "$#" -eq 0 ]; then
          echo "Usage: waypipe-${name} <application> [args…]" >&2
          exit 1
        fi
        exec waypipe ssh -p ${toString h.ssh.port} ${lib.escapeShellArg name} "$@"
      '';
    };

  homelabBookmarks =
    config.network.hosts
    |> lib.mapAttrsToList (
      _: host:
        host.publicWebServices
        |> lib.filterAttrs (_: service: service.bookmark)
        |> lib.mapAttrsToList (
          _: service:
            lib.nameValuePair service.title "https://${lib.optionalString (service.subdomain != null) "${service.subdomain}."}${config.identity.homelab.dns}${service.path}"
        )
    )
    |> lib.concatLists
    |> builtins.listToAttrs;
in {
  environment.systemPackages = lib.optionals accessible [zed.remote_server pkgs.waypipe];

  home-manager.sharedModules = [
    ({config, ...}: {
      # Zed checks this versioned path before attempting a download or upload.
      home.file.".zed_server/${zed.remoteServerExecutableName}" = lib.mkIf accessible {
        source = "${zed.remote_server}/bin/${zed.remoteServerExecutableName}";
      };

      home.packages = lib.optionals self.tailscale.enable (lib.mapAttrsToList waypipeFor otherHosts);
      gtk.gtk3.bookmarks = lib.mkIf (self.tailscale.enable && config.gtk.enable) (lib.mapAttrsToList bookmarkFor otherHosts);
      programs.ssh = lib.mkIf self.tailscale.enable {
        enable = true;
        matchBlocks = lib.mapAttrs sshMatchBlockFor otherHosts;
      };
      programs.zed-editor.userSettings.ssh_connections = lib.mkIf (self.tailscale.enable && config.programs.zed-editor.enable) (
        lib.mapAttrsToList (name: h: {
          host = name;
          port = h.ssh.port;
          username = config.identity.user.name;
        })
        otherHosts
      );
    })
  ];

  home-manager.users.${config.identity.user.name} = {config, ...}: {
    identity.firefox.homelabBookmarks = lib.mkIf (config.programs.firefox.enable && self.tailscale.enable) homelabBookmarks;
  };
}
