{
  config,
  lib,
  pkgs,
  ...
}: let
  remoteBuildUser = "nix-ssh";
  hostKeys = config.identity.ssh.hostKeys;
  thisHostName = config.networking.hostName;
  thisHost =
    config.network.hosts.${thisHostName}
    or (throw "host '${thisHostName}' is missing from network.hosts");

  providers =
    config.network.hosts
    |> lib.filterAttrs (_: host: host.buildCluster.builders.provide.enable);
  selectedProviderNames = thisHost.buildCluster.builders.use.providers;
  selectedProviders =
    providers
    |> lib.filterAttrs (name: _: lib.elem name selectedProviderNames);
  eligibleProviders =
    selectedProviders
    |> lib.filterAttrs (name: host: name != thisHostName && host.system == thisHost.system)
    |> lib.mapAttrsToList (name: host: {inherit name host;})
    |> lib.sort (a: b: a.host.buildCluster.builders.provide.speedFactor > b.host.buildCluster.builders.provide.speedFactor);
  users =
    config.network.hosts
    |> lib.filterAttrs (_: host: host.buildCluster.builders.use.enable);

  builderHostName = name: "${name}.ts.${config.identity.homelab.dns}";
  hasHostKey = name: builtins.hasAttr name hostKeys;

  providersWithHostKeys = lib.filter (provider: hasHostKey provider.name) eligibleProviders;
  remoteUsersWithHostKeys =
    users
    |> lib.filterAttrs (
      name: host:
        name
        != thisHostName
        && hasHostKey name
        && lib.elem thisHostName host.buildCluster.builders.use.providers
    );

  buildMachines =
    map (provider: {
      hostName = builderHostName provider.name;
      protocol = "ssh-ng";
      sshUser = remoteBuildUser;
      sshKey = "/etc/ssh/ssh_host_ed25519_key";
      system = provider.host.system;
      maxJobs = provider.host.buildCluster.builders.provide.maxJobs;
      speedFactor = provider.host.buildCluster.builders.provide.speedFactor;
      # Registry-declared providers are intentionally beefy, multi-core hosts.
      supportedFeatures = ["big-parallel"];
    })
    eligibleProviders;

  knownBuilderHosts = builtins.listToAttrs (map (provider: let
      hostName = builderHostName provider.name;
      port = provider.host.ssh.port;
    in {
      name = "nix-builder-${provider.name}";
      value = {
        hostNames = [
          (
            if port == 22
            then hostName
            else "[${hostName}]:${toString port}"
          )
        ];
        publicKey = hostKeys.${provider.name};
      };
    })
    providersWithHostKeys);

  builderSshConfig =
    lib.concatMapStringsSep "\n" (provider: ''
      Host ${builderHostName provider.name}
        Port ${toString provider.host.ssh.port}
    '')
    eligibleProviders;

  unknownProviderNames =
    lib.filter (name: !builtins.hasAttr name config.network.hosts) selectedProviderNames;
  disabledProviderNames =
    lib.filter (
      name:
        builtins.hasAttr name config.network.hosts
        && !config.network.hosts.${name}.buildCluster.builders.provide.enable
    )
    selectedProviderNames;
  selfProviderNames = lib.filter (name: name == thisHostName) selectedProviderNames;
  incompatibleProviderNames =
    lib.filter (
      name:
        builtins.hasAttr name providers
        && config.network.hosts.${name}.system != thisHost.system
    )
    selectedProviderNames;

  providesBuilds = host: host.buildCluster.builders.provide.enable;
  usesBuilders = host: host.buildCluster.builders.use.enable;
  explicitlyProvidesCache = host: host.buildCluster.cache.provide.enable;
  servesCache = host: providesBuilds host || explicitlyProvidesCache host;
  participates = host: servesCache host || usesBuilders host;
  cachePriority = host:
    if explicitlyProvidesCache host
    then host.buildCluster.cache.provide.priority
    else lib.max 1 (builtins.div 1000 host.buildCluster.builders.provide.speedFactor);

  peers =
    if participates thisHost && thisHost.tailscale.enable
    then
      config.network.hosts
      |> lib.filterAttrs (name: host: name != thisHostName && servesCache host)
      |> lib.mapAttrsToList (name: host: {
        inherit name host;
        priority = cachePriority host;
      })
      |> lib.sort (a: b: a.priority < b.priority)
    else [];

  proxyPort = 6000;
  proxyPathFor = peer: "${toString peer.priority}-${peer.name}";

  peerSubstituters =
    map (
      peer: "http://127.0.0.1:${toString proxyPort}/${proxyPathFor peer}"
    )
    peers;

  proxyLocations =
    builtins.listToAttrs (lib.concatMap (peer: [
        {
          name = "= /${proxyPathFor peer}/nix-cache-info";
          value = {
            alias = pkgs.writeText "nix-cache-info-${peer.name}" ''
              StoreDir: /nix/store
              WantMassQuery: 1
              Priority: ${toString peer.priority}
            '';
            extraConfig = "default_type text/plain;";
          };
        }
        {
          name = "/${proxyPathFor peer}/";
          value = {
            # A variable defers DNS resolution until request time, so an offline
            # cache peer cannot prevent Nginx from starting.
            proxyPass = "http://$cache_peer:${toString peer.host.buildCluster.cache.provide.port}";
            extraConfig = ''
              set $cache_peer ${builderHostName peer.name};
              rewrite ^/${proxyPathFor peer}/(.*)$ /$1 break;
              proxy_connect_timeout 500ms;
              proxy_read_timeout 5m;
              proxy_buffering off;
              proxy_request_buffering off;
              proxy_intercept_errors on;
              error_page 500 502 503 504 = @cache_miss;
            '';
          };
        }
      ])
      peers)
    // {"@cache_miss".return = 404;};

  proxyVirtualHost = {
    listen = [
      {
        addr = "127.0.0.1";
        port = proxyPort;
      }
    ];
    extraConfig = ''
      access_log off;
      error_log /dev/null crit;
    '';
    locations = proxyLocations;
  };

  cachePublicKey =
    builtins.readFile ../../secrets/nix-cache-public-key
    |> lib.removeSuffix "\n";
in {
  age = lib.mkIf (servesCache thisHost) {
    identityPaths = ["/etc/ssh/ssh_host_ed25519_key"];
    secrets.nix-cache-private-key.file = ../../secrets/nix-cache-private-key.age;
  };

  services.nix-serve = lib.mkIf (servesCache thisHost) {
    enable = true;
    bindAddress = "0.0.0.0";
    port = thisHost.buildCluster.cache.provide.port;
    secretKeyFile = config.age.secrets.nix-cache-private-key.path;
  };

  systemd.services.nix-serve.restartTriggers =
    lib.mkIf (servesCache thisHost) [../../secrets/nix-cache-private-key.age];

  networking.firewall.interfaces.tailscale0.allowedTCPPorts =
    lib.mkIf (servesCache thisHost) [thisHost.buildCluster.cache.provide.port];

  services.nginx = lib.mkIf (peers != []) {
    enable = true;
    resolver = {
      addresses = ["100.100.100.100"];
      valid = "30s";
      ipv6 = false;
    };
    virtualHosts.nix-cache-mesh = proxyVirtualHost;
  };

  # The peer proxies do not write file logs, so Nginx's default logrotate
  # entry would only inspect an unused /var/log/nginx glob.
  services.logrotate.settings.nginx.enable = lib.mkIf (peers != []) false;

  nix = {
    distributedBuilds = lib.mkIf (usesBuilders thisHost) true;
    buildMachines = lib.mkIf (usesBuilders thisHost) buildMachines;

    settings = {
      max-jobs = lib.mkIf (usesBuilders thisHost) thisHost.buildCluster.builders.use.localJobs;
      builders-use-substitutes = lib.mkIf (usesBuilders thisHost) true;

      substituters = lib.mkBefore peerSubstituters;
      trusted-public-keys = lib.mkBefore [cachePublicKey];

      # Peer proxy failures become immediate cache misses. Keep fallback enabled
      # for the rare case where a peer disappears during an active NAR transfer.
      fallback = true;

      # These caches expose live stores that can gain paths during the same
      # distributed build, so a cached miss must not hide newly built outputs.
      narinfo-cache-negative-ttl = lib.mkIf (peers != []) 0;
    };

    # This creates a forced-command SSH account that can only speak the Nix
    # daemon protocol; builder-user keys do not receive an interactive shell.
    sshServe = lib.mkIf (providesBuilds thisHost) {
      enable = true;
      protocol = "ssh-ng";
      trusted = true;
      keys =
        remoteUsersWithHostKeys
        |> lib.mapAttrsToList (name: _: hostKeys.${name});
    };
  };

  programs.ssh = lib.mkIf (usesBuilders thisHost) {
    knownHosts = knownBuilderHosts;
    extraConfig = builderSshConfig;
  };

  assertions =
    [
      {
        assertion = !(usesBuilders thisHost) || (thisHost.tailscale.enable && thisHost.ssh.enable);
        message = "A host using build-cluster providers must enable Tailscale and SSH.";
      }
      {
        assertion = !(providesBuilds thisHost && usesBuilders thisHost);
        message = "A build provider cannot use remote builders; providers must terminate distributed builds.";
      }
      {
        assertion = !(usesBuilders thisHost) || selectedProviderNames != [];
        message = "A host using the build cluster must select at least one provider.";
      }
      {
        assertion = lib.length selectedProviderNames == lib.length (lib.unique selectedProviderNames);
        message = "Build provider selections must not contain duplicates.";
      }
      {
        assertion = unknownProviderNames == [];
        message = "Unknown build providers selected by '${thisHostName}': ${lib.concatStringsSep ", " unknownProviderNames}.";
      }
      {
        assertion = disabledProviderNames == [];
        message = "Hosts selected by '${thisHostName}' that do not provide builds: ${lib.concatStringsSep ", " disabledProviderNames}.";
      }
      {
        assertion = selfProviderNames == [];
        message = "Host '${thisHostName}' cannot select itself as a build provider.";
      }
      {
        assertion = incompatibleProviderNames == [];
        message = "Build providers selected by '${thisHostName}' with an incompatible system: ${lib.concatStringsSep ", " incompatibleProviderNames}.";
      }
      {
        assertion = !(usesBuilders thisHost) || eligibleProviders != [];
        message = "A host using the build cluster must have at least one selected provider for ${thisHost.system}.";
      }
      {
        assertion = !(participates thisHost) || thisHost.tailscale.enable;
        message = "A build-cluster participant must enable Tailscale.";
      }
    ]
    ++ lib.mapAttrsToList (name: host: {
      assertion = host.ssh.enable && host.tailscale.enable;
      message = "Build provider '${name}' must enable SSH and Tailscale.";
    })
    providers
    ++ lib.mapAttrsToList (name: _: {
      assertion = hasHostKey name;
      message = "Build provider '${name}' needs an identity.ssh.hostKeys entry.";
    })
    providers
    ++ lib.mapAttrsToList (name: _: {
      assertion = hasHostKey name;
      message = "Builder user '${name}' needs an identity.ssh.hostKeys entry.";
    })
    users;
}
