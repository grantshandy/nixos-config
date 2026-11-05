{
  config,
  lib,
  pkgs,
  ...
}: let
  tokenFile = ../../secrets/gitlab-runner-token.age;
  tokenAvailable = builtins.pathExists tokenFile;

  namespace = "uofu-ci";
  hostInterface = "${namespace}-host";
  namespaceInterface = "${namespace}-peer";
  tunnelInterface = "${namespace}-vpn";
  runtimeDir = "/run/${namespace}";
  runnerBuildDir = "/var/lib/gitlab-runner-builds";
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

          ip address add 10.203.0.1/30 dev ${hostInterface}
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
          systemctl restart gitlab-runner.service
          echo "University VPN and GitLab Runner are active"
          exit 0
        fi
        sleep 1
      done

      echo "OpenConnect did not create ${tunnelInterface} within 30 seconds" >&2
      systemctl --no-pager --full status ${namespace}-vpn.service >&2 || true
      exit 1
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

    environment.systemPackages = [
      submitAuth
      vpnStatus
    ];

    users.groups.gitlab-runner = {};
    users.users.gitlab-runner = {
      isSystemUser = true;
      group = "gitlab-runner";
      home = "/var/lib/gitlab-runner";
    };

    systemd.tmpfiles.rules = [
      "d ${runtimeDir} 0700 root root -"
      "d ${runnerBuildDir} 0750 gitlab-runner gitlab-runner -"
    ];

    systemd.services."${namespace}-netns" = {
      description = "Network namespace for University VPN CI traffic";
      wantedBy = ["multi-user.target"];
      before = ["${namespace}-vpn.service" "gitlab-runner.service"];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = "${lib.getExe namespaceSetup} start";
        ExecStop = "${lib.getExe namespaceSetup} stop";
      };
    };

    systemd.services."${namespace}-vpn" = {
      description = "University of Utah VPN for GitLab Runner";
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

    services.gitlab-runner = {
      enable = true;
      settings.concurrent = 1;
      extraPackages = [
        config.nix.package
        pkgs.git
      ];

      services.radon-nix = {
        authenticationTokenConfigFile = config.age.secrets.gitlab-runner-token.path;
        executor = "shell";
        description = "radon-nix";
        # StateDirectory is intentionally noexec; job workspaces must execute
        # pnpm launchers, Cargo build scripts, and compiled test binaries.
        buildsDir = runnerBuildDir;
        environmentVariables.NIX_CONFIG = ''
          experimental-features = nix-command flakes pipe-operators
        '';
      };
    };

    system.build.uofuCiSupport = pkgs.symlinkJoin {
      name = "uofu-ci-support";
      paths = [
        namespaceSetup
        vpnStart
        submitAuth
        vpnStatus
      ];
    };

    systemd.services.gitlab-runner = {
      # Authentication explicitly starts the runner; do not fail boot or
      # nixos-rebuild while no ephemeral SAML cookie exists.
      wantedBy = lib.mkForce [];
      requires = ["${namespace}-netns.service" "${namespace}-vpn.service"];
      after = ["${namespace}-netns.service" "${namespace}-vpn.service"];
      bindsTo = ["${namespace}-vpn.service"];
      serviceConfig = {
        NetworkNamespacePath = "/run/netns/${namespace}";
        BindReadOnlyPaths = ["${runtimeDir}/resolv.conf:/etc/resolv.conf"];
        # DynamicUser mounts StateDirectory with noexec, which prevents shell
        # jobs from running package-manager tools and Cargo build scripts.
        DynamicUser = lib.mkForce false;
        User = "gitlab-runner";
        Group = "gitlab-runner";
        Nice = 10;
        CPUWeight = 25;
        IOWeight = 25;
        OOMScoreAdjust = 500;
      };
    };
  }
