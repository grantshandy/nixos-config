{
  config,
  lib,
  ...
}: let
  remoteBuildUser = "nix-ssh";
  hostKeys = config.identity.ssh.hostKeys;
  thisHostName = config.networking.hostName;
  thisHost =
    config.network.hosts.${thisHostName}
    or (throw "host '${thisHostName}' is missing from network.hosts");

  allBuilders =
    config.network.hosts
    |> lib.filterAttrs (_: host: host.remoteBuilder.push);
  eligibleBuilders =
    allBuilders
    |> lib.filterAttrs (_: host: host.system == thisHost.system)
    |> lib.mapAttrsToList (name: host: {inherit name host;})
    |> lib.sort (a: b: a.host.remoteBuilder.priority < b.host.remoteBuilder.priority);
  consumers =
    config.network.hosts
    |> lib.filterAttrs (_: host: host.remoteBuilder.pull);

  builderHostName = name: "${name}.ts.${config.identity.homelab.dns}";
  builderSpeedFactor = host: lib.max 1 (builtins.div 1000 host.remoteBuilder.priority);
  hasHostKey = name: builtins.hasAttr name hostKeys;

  buildersWithHostKeys = lib.filter (builder: hasHostKey builder.name) eligibleBuilders;
  consumersWithHostKeys = lib.filterAttrs (name: _: hasHostKey name) consumers;

  buildMachines =
    map (builder: {
      hostName = builderHostName builder.name;
      protocol = "ssh-ng";
      sshUser = remoteBuildUser;
      sshKey = "/etc/ssh/ssh_host_ed25519_key";
      system = builder.host.system;
      maxJobs = builder.host.remoteBuilder.maxJobs;
      speedFactor = builderSpeedFactor builder.host;
    })
    eligibleBuilders;

  knownBuilderHosts = builtins.listToAttrs (map (builder: let
      hostName = builderHostName builder.name;
      port = builder.host.ssh.port;
    in {
      name = "nix-builder-${builder.name}";
      value = {
        hostNames = [
          (
            if port == 22
            then hostName
            else "[${hostName}]:${toString port}"
          )
        ];
        publicKey = hostKeys.${builder.name};
      };
    })
    buildersWithHostKeys);

  builderSshConfig =
    lib.concatMapStringsSep "\n" (builder: ''
      Host ${builderHostName builder.name}
        Port ${toString builder.host.ssh.port}
    '')
    eligibleBuilders;
in {
  nix = {
    distributedBuilds = lib.mkIf thisHost.remoteBuilder.pull true;
    buildMachines = lib.mkIf thisHost.remoteBuilder.pull buildMachines;

    settings = {
      # A consumer must never fall back to building locally. Nix will schedule
      # against another declared builder when the preferred one is unavailable.
      max-jobs = lib.mkIf thisHost.remoteBuilder.pull 0;
      builders-use-substitutes = lib.mkIf thisHost.remoteBuilder.pull true;
    };

    # This creates a forced-command SSH account that can only speak the Nix
    # daemon protocol; consumer keys do not receive an interactive shell.
    sshServe = lib.mkIf thisHost.remoteBuilder.push {
      enable = true;
      protocol = "ssh-ng";
      trusted = true;
      keys =
        consumersWithHostKeys
        |> lib.mapAttrsToList (name: _: hostKeys.${name});
    };
  };

  programs.ssh = lib.mkIf thisHost.remoteBuilder.pull {
    knownHosts = knownBuilderHosts;
    extraConfig = builderSshConfig;
  };

  assertions =
    [
      {
        assertion = !thisHost.remoteBuilder.pull || (thisHost.tailscale.enable && thisHost.ssh.enable);
        message = "A host pulling from remote builders must enable Tailscale and SSH.";
      }
      {
        assertion = !thisHost.remoteBuilder.pull || eligibleBuilders != [];
        message = "A remote-build consumer must have at least one builder for ${thisHost.system}.";
      }
    ]
    ++ lib.mapAttrsToList (name: host: {
      assertion = host.ssh.enable && host.tailscale.enable;
      message = "Remote builder '${name}' must enable SSH and Tailscale.";
    })
    allBuilders
    ++ lib.mapAttrsToList (name: _: {
      assertion = hasHostKey name;
      message = "Remote builder '${name}' needs an identity.ssh.hostKeys entry.";
    })
    allBuilders
    ++ lib.mapAttrsToList (name: _: {
      assertion = hasHostKey name;
      message = "Remote-build consumer '${name}' needs an identity.ssh.hostKeys entry.";
    })
    consumers;
}
