# Reaching the other machines in the fleet. General SSH/SFTP access is separate
# from remote-development tooling so minimal hosts can remain reachable without
# installing Waypipe or the Zed remote server. Home Manager reads the current
# host from `osConfig` rather than receiving it through `extraSpecialArgs`.
# Homelab bookmarks come from the fleet-wide service registry.
{
  config,
  lib,
  ...
}: let
  fleet = config.fleet;
  tailnetDomain = "ts.${fleet.identity.homelab.dns}";

  reachable = host: host.ssh.enable && host.tailscale.enable;
  peersOf = hostName:
    fleet.hosts
    |> lib.filterAttrs (name: host: name != hostName && reachable host);

  developmentHosts =
    fleet.hosts
    |> lib.filterAttrs (_: host: reachable host && host.remoteDevelopment.enable);

  developmentPeersOf = hostName: removeAttrs developmentHosts [hostName];

  homelabBookmarks =
    fleet.services
    |> lib.attrValues
    |> lib.filter (service: service.public && service.bookmark)
    |> map (service: lib.nameValuePair service.title service.url)
    |> builtins.listToAttrs;

  bookmarkFor = userName: name: host: "sftp://${name}:${toString host.ssh.port}/home/${userName}/ ${name}";

  sshSettingsFor = userName: name: host: {
    HostName = "${name}.${tailnetDomain}";
    Port = host.ssh.port;
    User = userName;
  };
in {
  # The machines you work *from*: the same set that gets a Home Manager profile.
  fleet.aspects.remote-access.hosts =
    config.fleet.hosts
    |> lib.filterAttrs (_: host: host.homeManager.enable)
    |> lib.attrNames;

  # Remote-development targets are independently selectable from the machines
  # whose user profiles contain general remote-access configuration.
  fleet.aspects.remote-development.hosts = lib.attrNames developmentHosts;

  flake.modules.nixos.remote-development = {
    pkgs,
    pkgs-unstable,
    ...
  }: {
    environment.systemPackages = [
      pkgs-unstable.zed-editor.remote_server
      pkgs.waypipe
    ];
  };

  flake.modules.homeManager.remote-development = {
    config,
    lib,
    osConfig,
    pkgs,
    pkgs-unstable,
    ...
  }: let
    hostName = osConfig.networking.hostName;
    peers = developmentPeersOf hostName;
    userName = config.identity.user.name;
    zed = pkgs-unstable.zed-editor;

    waypipeFor = name: host:
      pkgs.writeShellApplication {
        name = "waypipe-${name}";
        runtimeInputs = [pkgs.waypipe pkgs.openssh];
        text = ''
          if [ "$#" -eq 0 ]; then
            echo "Usage: waypipe-${name} <application> [args…]" >&2
            exit 1
          fi
          exec waypipe ssh -p ${toString host.ssh.port} ${lib.escapeShellArg name} "$@"
        '';
      };
  in {
    # Zed checks this versioned path before attempting a download or upload.
    home.file.".zed_server/${zed.remoteServerExecutableName}".source = "${zed.remote_server}/bin/${zed.remoteServerExecutableName}";

    home.packages = lib.mapAttrsToList waypipeFor peers;

    programs.zed-editor.userSettings.ssh_connections =
      lib.mkIf config.programs.zed-editor.enable
      (lib.mapAttrsToList (name: host: {
          host = name;
          port = host.ssh.port;
          username = userName;
        })
        peers);
  };

  flake.modules.homeManager.remote-access = {
    config,
    lib,
    osConfig,
    ...
  }: let
    hostName = osConfig.networking.hostName;
    self = fleet.hosts.${hostName};
    peers = peersOf hostName;
    userName = config.identity.user.name;
  in {
    gtk.gtk3.bookmarks =
      lib.mkIf (self.tailscale.enable && config.gtk.enable)
      (lib.mapAttrsToList (bookmarkFor userName) peers);

    xdg.configFile."gtk-3.0/bookmarks" =
      lib.mkIf (self.tailscale.enable && config.gtk.enable) {force = true;};

    programs.ssh = lib.mkIf self.tailscale.enable {
      enable = true;
      enableDefaultConfig = false;
      settings =
        {
          "*" = {
            ForwardAgent = false;
            AddKeysToAgent = "no";
            Compression = false;
            ServerAliveInterval = 0;
            ServerAliveCountMax = 3;
            HashKnownHosts = false;
            UserKnownHostsFile = "~/.ssh/known_hosts";
            ControlMaster = "no";
            ControlPath = "~/.ssh/master-%r@%n:%p";
            ControlPersist = "no";
          };
        }
        // lib.mapAttrs (sshSettingsFor userName) peers;
    };

    identity.firefox.homelabBookmarks =
      lib.mkIf (config.programs.firefox.enable && self.tailscale.enable)
      homelabBookmarks;
  };
}
