{
  config,
  lib,
  pkgs,
  utils,
  radonMediaRoot,
  ...
}: let
  tokenFile = ../../secrets/gitlab-runner-token.age;
  tokenAvailable = builtins.pathExists tokenFile;

  namespace = "uofu-ci";
  hostInterface = "${namespace}-host";
  hostAddress = "10.203.0.1";
  namespaceInterface = "${namespace}-peer";
  tunnelInterface = "${namespace}-vpn";
  nixCacheProxyPort = 6000;
  runtimeDir = "/run/${namespace}";
  podmanRuntimeDir = "/run/${namespace}-podman";
  mediaMount = radonMediaRoot;
  mediaMountUnit = "${utils.escapeSystemdPath mediaMount}.mount";
  runnerBuildDir = "${mediaMount}/gitlab-runner-builds";
  runnerCacheDir = "${mediaMount}/gitlab-runner-cache";
  gitlabCacheDir = "${runnerCacheDir}/gitlab";
  podmanDataDir = "${runnerCacheDir}/podman";
  podmanNetworkDir = "${podmanDataDir}/networks";
  podmanTmpDir = "${podmanRuntimeDir}/tmp";
  containerNixDir = "${runnerCacheDir}/nix-container";
  podmanSocket = "${podmanRuntimeDir}/podman.sock";
  podmanRunRoot = "${podmanRuntimeDir}/storage";
  podmanPackage = config.virtualisation.podman.package;
  podmanStorageConfig = pkgs.writeText "${namespace}-storage.conf" ''
    [storage]
    driver = "overlay"
    graphroot = "${podmanDataDir}"
    runroot = "${podmanRunRoot}"
  '';
  nixImageDigest = "sha256:a3b3e3eb3883e5af5327757c5304c0093426a0d11c58a9056df46cfefe30319e";
  nixImage = "nixos/nix@${nixImageDigest}";
  nixSeedMarker = ".uofu-ci-store-db-seeded-${builtins.substring 7 12 nixImageDigest}";
  legacyNixSeedMarker = ".uofu-ci-seeded-${builtins.substring 7 12 nixImageDigest}";
  cargoTargetDir = "${runnerCacheDir}/auxq-cargo-target";
  androidCargoTargetDir = "${runnerCacheDir}/auxq-android-cargo-target";
  cargoHomeDir = "${runnerCacheDir}/auxq-cargo-home";
  gradleHomeDir = "${runnerCacheDir}/auxq-gradle-home";
  pnpmStoreDir = "${runnerCacheDir}/pnpm-store";
  nixBuildDir = "${runnerCacheDir}/auxq-nix-build";
  nixXdgCacheDir = "${runnerCacheDir}/auxq-nix-xdg-cache";
  nixTmpDir = "${runnerCacheDir}/auxq-nix-tmp";
  ciSubstituters =
    config.nix.settings.substituters
    |> map (lib.replaceStrings
      ["http://127.0.0.1:${toString nixCacheProxyPort}"]
      ["http://${hostAddress}:${toString nixCacheProxyPort}"]);
  ciTrustedPublicKeys = config.nix.settings.trusted-public-keys;
  vpnServer = "vpn.utah.edu";

  namespaceSetup = pkgs.writeShellApplication {
    name = "${namespace}-netns";
    runtimeInputs = with pkgs; [coreutils gnugrep iproute2 nftables];
    text = ''
      case "''${1:-}" in
        start)
          if ip netns list | grep -q '^${namespace}\b'; then
            ip netns delete ${namespace}
          fi
          ip link delete ${hostInterface} 2>/dev/null || true

          ip netns add ${namespace}
          ip link add ${hostInterface} type veth peer name ${namespaceInterface}
          ip link set ${namespaceInterface} netns ${namespace}

          ip address add ${hostAddress}/30 dev ${hostInterface}
          ip link set ${hostInterface} up
          ip -n ${namespace} link set lo up
          ip -n ${namespace} address add 10.203.0.2/30 dev ${namespaceInterface}
          ip -n ${namespace} link set ${namespaceInterface} up
          ip -n ${namespace} route add default via 10.203.0.1

          ip netns exec ${namespace} nft -f - <<'EOF'
      table inet uofu_ci {
        chain output {
          type filter hook output priority filter; policy drop;
          oifname "lo" accept
          ct state established,related accept
          meta skuid 0 oifname "${namespaceInterface}" accept
          oifname "${tunnelInterface}" accept
        }

        chain forward {
          type filter hook forward priority filter; policy drop;
          ct state established,related accept
          iifname "podman*" ip daddr ${hostAddress} tcp dport ${toString nixCacheProxyPort} accept
          iifname "podman*" oifname "podman*" accept
          oifname "${tunnelInterface}" accept
        }
      }
      EOF

          install -d -m 0700 ${runtimeDir}
          cp /etc/resolv.conf ${runtimeDir}/resolv.conf
          chmod 0644 ${runtimeDir}/resolv.conf
          ;;
        stop)
          ip netns delete ${namespace} 2>/dev/null || true
          ip link delete ${hostInterface} 2>/dev/null || true
          ;;
        *)
          echo "Usage: ${namespace}-netns {start|stop}" >&2
          exit 2
          ;;
      esac
    '';
  };

  vpncScript = pkgs.writeShellScript "${namespace}-vpnc-script" ''
    set -eu

    dns_servers="''${INTERNAL_IP4_DNS:-} ''${INTERNAL_IP6_DNS:-}"
    case "''${reason:-}" in
      connect | reconnect)
        : >${runtimeDir}/resolv.conf.new
        for server in $dns_servers; do
          printf 'nameserver %s\n' "$server" >>${runtimeDir}/resolv.conf.new
        done
        if [ ! -s ${runtimeDir}/resolv.conf.new ]; then
          cp /etc/resolv.conf ${runtimeDir}/resolv.conf.new
        fi
        chmod 0644 ${runtimeDir}/resolv.conf.new
        mv ${runtimeDir}/resolv.conf.new ${runtimeDir}/resolv.conf
        ;;
    esac

    unset INTERNAL_IP4_DNS INTERNAL_IP6_DNS CISCO_DEF_DOMAIN CISCO_SPLIT_DNS
    exec ${pkgs.vpnc-scripts}/bin/vpnc-script
  '';

  vpnStart = pkgs.writeShellApplication {
    name = "${namespace}-vpn-start";
    runtimeInputs = with pkgs; [coreutils gawk gnugrep gnused iproute2 openconnect];
    text = ''
      for field in host user cookie os; do
        if [ ! -s "${runtimeDir}/$field" ]; then
          echo "VPN authentication is missing; run uofu-runner-vpn renew from Xenon" >&2
          exit 1
        fi
      done

      host="$(cat ${runtimeDir}/host)"
      user="$(cat ${runtimeDir}/user)"
      cookie="$(cat ${runtimeDir}/cookie)"
      os="$(cat ${runtimeDir}/os)"

      # vpnc-script removes the underlay default route when a VPN session ends.
      # Restore it before OpenConnect needs to contact the VPN gateway again.
      ip route replace default via 10.203.0.1 dev ${namespaceInterface}

      printf '%s\n' "$cookie" | exec openconnect \
        --protocol=gp \
        --interface=${tunnelInterface} \
        --script=${vpncScript} \
        --user="$user" \
        --os="$os" \
        --passwd-on-stdin \
        --non-inter \
        "$host"
    '';
  };

  submitAuth = pkgs.writeShellApplication {
    name = "${namespace}-submit-auth";
    runtimeInputs = with pkgs; [coreutils iproute2 systemd];
    text = ''
      if [ "$(id -u)" -ne 0 ]; then
        echo "${namespace}-submit-auth must run as root" >&2
        exit 1
      fi

      IFS= read -r host
      IFS= read -r user
      IFS= read -r cookie
      IFS= read -r os

      case "$host" in
        https://${vpnServer} | https://${vpnServer}/*) ;;
        *)
          echo "Refusing credentials for an unexpected VPN host" >&2
          exit 1
          ;;
      esac
      case "$os" in
        win | linux | linux-64 | mac-intel) ;;
        *)
          echo "Refusing an unexpected OpenConnect OS value" >&2
          exit 1
          ;;
      esac
      if [ -z "$user" ] || [ -z "$cookie" ]; then
        echo "The VPN authentication response was incomplete" >&2
        exit 1
      fi

      install -d -m 0700 ${runtimeDir}
      umask 0077
      printf '%s\n' "$host" >${runtimeDir}/host.new
      printf '%s\n' "$user" >${runtimeDir}/user.new
      printf '%s\n' "$cookie" >${runtimeDir}/cookie.new
      printf '%s\n' "$os" >${runtimeDir}/os.new
      for field in host user cookie os; do
        mv "${runtimeDir}/$field.new" "${runtimeDir}/$field"
      done

      systemctl restart ${namespace}-vpn.service
      for _ in $(seq 1 30); do
        if ip -n ${namespace} link show ${tunnelInterface} >/dev/null 2>&1; then
          systemctl restart ${namespace}-podman.service
          systemctl restart ${namespace}-podman-setup.service
          systemctl restart gitlab-runner.service
          echo "University VPN, CI container runtime, and GitLab Runner are active"
          exit 0
        fi
        sleep 1
      done

      echo "OpenConnect did not create ${tunnelInterface} within 30 seconds" >&2
      systemctl --no-pager --full status ${namespace}-vpn.service >&2 || true
      exit 1
    '';
  };

  podmanSetup = pkgs.writeShellApplication {
    name = "${namespace}-podman-setup";
    runtimeInputs = [pkgs.coreutils pkgs.findutils podmanPackage];
    text = ''
      podman=(podman --remote --url unix://${podmanSocket})

      if ! "''${podman[@]}" image inspect ${nixImage} >/dev/null 2>&1; then
        "''${podman[@]}" pull ${nixImage}
      fi

      # Persist the store and its validity database without replacing all of
      # /nix. A whole-/nix mount hides the image-owned profiles that provide
      # sh and the basic tools GitLab Runner needs before the job can begin.
      # Re-seed when the pinned image changes so its profile targets are
      # guaranteed to exist in the persistent store.
      if [ ! -e ${containerNixDir}/${nixSeedMarker} ]; then
        if {
          [ -e ${containerNixDir}/${legacyNixSeedMarker} ] ||
          [ -e ${containerNixDir}/.uofu-ci-seeded ]
        } && [ -d ${containerNixDir}/store ] && [ -d ${containerNixDir}/var/nix/db ]; then
          # Migrate the previous whole-/nix layout without discarding its cache.
          mv ${containerNixDir}/var/nix/db ${containerNixDir}/db
          rm -rf ${containerNixDir}/var
          touch ${containerNixDir}/${nixSeedMarker}
        else
          find ${containerNixDir} -mindepth 1 -delete
          "''${podman[@]}" run --rm \
            --entrypoint /bin/sh \
            --volume ${containerNixDir}:/ci-nix \
            ${nixImage} \
            -euc '
              cp -a /nix/store /ci-nix/store
              cp -a /nix/var/nix/db /ci-nix/db
              touch /ci-nix/${nixSeedMarker}
            '
        fi
      fi

      "''${podman[@]}" run --rm \
        --entrypoint /bin/sh \
        --volume ${containerNixDir}/store:/nix/store \
        --volume ${containerNixDir}/db:/nix/var/nix/db \
        ${nixImage} \
        -euc 'command -v sh grep mkdir nix >/dev/null; nix --extra-experimental-features nix-command store verify --all --no-contents --no-trust'
    '';
  };

  vpnStatus = pkgs.writeShellApplication {
    name = "${namespace}-status";
    runtimeInputs = with pkgs; [coreutils curl gnused iproute2 systemd];
    text = ''
      if ! systemctl is-active --quiet ${namespace}-vpn.service; then
        echo needs-auth
        exit 1
      fi
      if ! ip -n ${namespace} link show ${tunnelInterface} >/dev/null 2>&1; then
        echo needs-auth
        exit 1
      fi

      url="$(sed -n 's/^CI_SERVER_URL=//p' ${config.age.secrets.gitlab-runner-token.path} | sed -n '1p')"
      case "$url" in
        http://* | https://*) ;;
        *)
          echo misconfigured
          exit 1
          ;;
      esac

      if ! ip netns exec ${namespace} curl --silent --show-error --max-time 10 --output /dev/null "$url"; then
        echo unreachable
        exit 1
      fi

      echo active
    '';
  };
in
  lib.mkIf tokenAvailable {
    age.secrets.gitlab-runner-token.file = tokenFile;

    networking.nat = {
      enable = true;
      externalInterface = "enp8s0";
      internalInterfaces = [hostInterface];
    };

    networking.firewall.interfaces.${hostInterface}.allowedTCPPorts = [nixCacheProxyPort];

    # The mesh proxy normally listens only on the host's loopback interface.
    # Expose it on the CI veth so containers can use it without access to the
    # host network namespace or the host's other services.
    services.nginx.virtualHosts.nix-cache-mesh.listen = lib.mkAfter [
      {
        addr = hostAddress;
        port = nixCacheProxyPort;
      }
    ];
    systemd.services.nginx.after = ["${namespace}-netns.service"];

    environment.systemPackages = [
      submitAuth
      vpnStatus
    ];

    virtualisation.podman.enable = true;

    users.groups.gitlab-runner = {};
    users.users.gitlab-runner = {
      isSystemUser = true;
      group = "gitlab-runner";
      home = "/var/lib/gitlab-runner";
    };

    systemd.tmpfiles.rules = [
      "d ${runtimeDir} 0700 root root -"
      "d ${podmanRuntimeDir} 0750 root gitlab-runner -"
      "d ${runnerBuildDir} 0750 gitlab-runner gitlab-runner -"
      "d ${runnerCacheDir} 0750 gitlab-runner gitlab-runner -"
      "d ${gitlabCacheDir} 0750 gitlab-runner gitlab-runner -"
      "d ${podmanDataDir} 0700 root root -"
      "d ${podmanNetworkDir} 0700 root root -"
      "d ${podmanTmpDir} 0700 root root -"
      "d ${containerNixDir} 0755 root root -"
      "d ${cargoTargetDir} 0750 gitlab-runner gitlab-runner -"
      "d ${androidCargoTargetDir} 0750 gitlab-runner gitlab-runner -"
      "d ${cargoHomeDir} 0750 gitlab-runner gitlab-runner -"
      "d ${gradleHomeDir} 0750 gitlab-runner gitlab-runner -"
      "d ${pnpmStoreDir} 0750 gitlab-runner gitlab-runner -"
      # The container runs Nix as root and creates temporary build directories here.
      "d ${nixBuildDir} 0755 root root -"
      "d ${nixXdgCacheDir} 0750 gitlab-runner gitlab-runner -"
      "d ${nixTmpDir} 0750 gitlab-runner gitlab-runner -"
    ];

    systemd.services."${namespace}-netns" = {
      description = "Network namespace for University VPN CI traffic";
      wantedBy = ["multi-user.target"];
      before = ["${namespace}-vpn.service" "${namespace}-podman.service" "gitlab-runner.service"];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = "${lib.getExe namespaceSetup} start";
        ExecStop = "${lib.getExe namespaceSetup} stop";
      };
    };

    systemd.services."${namespace}-vpn" = {
      description = "University of Utah VPN for GitLab Runner";
      # VPN authentication is ephemeral and must only be consumed by an
      # explicit authentication renewal, not by nixos-rebuild activation.
      restartIfChanged = false;
      requires = ["${namespace}-netns.service"];
      wants = ["network-online.target"];
      after = ["${namespace}-netns.service" "network-online.target"];
      serviceConfig = {
        Type = "simple";
        ExecStart = lib.getExe vpnStart;
        NetworkNamespacePath = "/run/netns/${namespace}";
        Restart = "no";
        KillMode = "mixed";
        TimeoutStopSec = "20s";
      };
    };

    systemd.sockets."${namespace}-podman" = {
      description = "Docker-compatible Podman API socket for GitLab CI";
      requires = ["${namespace}-vpn.service"];
      after = ["${namespace}-vpn.service"];
      bindsTo = ["${namespace}-vpn.service"];
      listenStreams = [podmanSocket];
      socketConfig = {
        SocketMode = "0660";
        SocketUser = "root";
        SocketGroup = "gitlab-runner";
        RemoveOnStop = true;
      };
    };

    systemd.services."${namespace}-podman" = {
      description = "Media-backed Podman API service for GitLab CI";
      restartIfChanged = false;
      requires = [
        "${namespace}-netns.service"
        "${namespace}-vpn.service"
        "${namespace}-podman.socket"
      ];
      after = [
        "${namespace}-netns.service"
        "${namespace}-vpn.service"
        "${namespace}-podman.socket"
        mediaMountUnit
      ];
      bindsTo = ["${namespace}-vpn.service" mediaMountUnit];
      unitConfig.RequiresMountsFor = [podmanDataDir];
      path = with pkgs; [iproute2 iptables kmod];
      environment = {
        CONTAINERS_STORAGE_CONF = podmanStorageConfig;
        TMPDIR = podmanTmpDir;
      };
      serviceConfig = {
        Type = "exec";
        ExecStart = ''
          ${podmanPackage}/bin/podman \
            --root=${podmanDataDir} \
            --runroot=${podmanRunRoot} \
            --tmpdir=${podmanTmpDir} \
            --storage-driver=overlay \
            --network-config-dir=${podmanNetworkDir} \
            system service --time=0
        '';
        NetworkNamespacePath = "/run/netns/${namespace}";
        BindReadOnlyPaths = ["${runtimeDir}/resolv.conf:/etc/resolv.conf"];
        Delegate = true;
        KillMode = "mixed";
        Restart = "on-failure";
        RestartSec = "5s";
        TimeoutStopSec = "30s";
        TasksMax = "infinity";
        LimitNOFILE = 1048576;
      };
    };

    systemd.services."${namespace}-podman-setup" = {
      description = "Prepare the persistent Nix CI container store";
      restartIfChanged = false;
      requires = ["${namespace}-podman.service"];
      after = ["${namespace}-podman.service"];
      bindsTo = [mediaMountUnit];
      unitConfig.RequiresMountsFor = [containerNixDir];
      serviceConfig = {
        Type = "oneshot";
        ExecStart = lib.getExe podmanSetup;
        RemainAfterExit = true;
        TimeoutStartSec = "15min";
      };
    };

    services.gitlab-runner = {
      enable = true;
      settings.concurrent = 1;
      services.radon-nix = {
        authenticationTokenConfigFile = config.age.secrets.gitlab-runner-token.path;
        executor = "docker";
        description = "radon-nix-container";
        buildsDir = runnerBuildDir;
        registrationFlags = [
          "--cache-dir ${gitlabCacheDir}"
          "--docker-host unix://${podmanSocket}"
        ];
        dockerImage = nixImage;
        dockerPullPolicy = "if-not-present";
        dockerVolumes = [
          # Preserve the image's /nix profiles while sharing its expensive
          # store contents and validity database across jobs on /mnt/media.
          "${containerNixDir}/store:/nix/store"
          "${containerNixDir}/db:/nix/var/nix/db"
          "${gitlabCacheDir}:${gitlabCacheDir}"
          "${cargoTargetDir}:${cargoTargetDir}"
          "${androidCargoTargetDir}:${androidCargoTargetDir}"
          "${cargoHomeDir}:${cargoHomeDir}"
          "${gradleHomeDir}:${gradleHomeDir}"
          "${pnpmStoreDir}:${pnpmStoreDir}"
          "${nixBuildDir}:${nixBuildDir}"
          "${nixXdgCacheDir}:${nixXdgCacheDir}"
          "${nixTmpDir}:${nixTmpDir}"
        ];
        environmentVariables = {
          NIX_CONFIG = ''
            experimental-features = nix-command flakes pipe-operators
            substituters = ${lib.concatStringsSep " " ciSubstituters}
            trusted-public-keys = ${lib.concatStringsSep " " ciTrustedPublicKeys}
            fallback = true
            sandbox = false
            build-dir = ${nixBuildDir}
          '';
          AUXQ_CI_CARGO_TARGET_DIR = cargoTargetDir;
          AUXQ_CI_ANDROID_CARGO_TARGET_DIR = androidCargoTargetDir;
          AUXQ_CI_CARGO_HOME = cargoHomeDir;
          AUXQ_CI_GRADLE_HOME = gradleHomeDir;
          AUXQ_CI_PNPM_STORE_DIR = pnpmStoreDir;
          AUXQ_CI_NIX_BUILD_DIR = nixBuildDir;
          AUXQ_CI_XDG_CACHE_HOME = nixXdgCacheDir;
          AUXQ_CI_TMPDIR = nixTmpDir;
          XDG_CACHE_HOME = nixXdgCacheDir;
          TMPDIR = nixTmpDir;
          # Do not override PATH here: runner variables are also injected into
          # helper containers, and each image must retain its own tool paths.
          # Required by GitLab Runner when its Docker executor targets Podman.
          FF_NETWORK_PER_BUILD = "1";
        };
      };
    };

    system.build.uofuCiSupport = pkgs.symlinkJoin {
      name = "uofu-ci-support";
      paths = [
        namespaceSetup
        vpnStart
        podmanSetup
        submitAuth
        vpnStatus
      ];
    };

    systemd.services.gitlab-runner = {
      # Authentication explicitly starts the runner. Keep rebuild activation
      # from restarting an active stack with an expired SAML cookie; the next
      # authentication renewal restarts every service with the new generation.
      wantedBy = lib.mkForce [];
      restartIfChanged = false;
      requires = [
        "${namespace}-netns.service"
        "${namespace}-vpn.service"
        "${namespace}-podman.service"
        "${namespace}-podman-setup.service"
      ];
      after = [
        "${namespace}-netns.service"
        "${namespace}-vpn.service"
        "${namespace}-podman.service"
        "${namespace}-podman-setup.service"
        mediaMountUnit
      ];
      bindsTo = ["${namespace}-vpn.service" "${namespace}-podman.service" mediaMountUnit];
      unitConfig.RequiresMountsFor = [runnerBuildDir runnerCacheDir];
      serviceConfig = {
        NetworkNamespacePath = "/run/netns/${namespace}";
        BindReadOnlyPaths = ["${runtimeDir}/resolv.conf:/etc/resolv.conf"];
        # A stable account is required to access the dedicated Podman socket and
        # the media-backed runner directories.
        DynamicUser = lib.mkForce false;
        User = "gitlab-runner";
        Group = "gitlab-runner";
        Nice = 10;
        CPUWeight = 75;
        IOWeight = 50;
        OOMScoreAdjust = 500;
      };
    };
  }
