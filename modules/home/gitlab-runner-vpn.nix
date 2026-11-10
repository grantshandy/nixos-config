{
  lib,
  pkgs,
  ...
}: let
  tokenAvailable = builtins.pathExists ../../secrets/gitlab-runner-token.age;
  serviceName = "uofu-runner-vpn-monitor";
  vpnServer = "vpn.utah.edu";

  monitor = pkgs.writeShellApplication {
    name = serviceName;
    runtimeInputs = with pkgs; [coreutils libnotify openssh];
    text = ''
      state_dir="''${XDG_STATE_HOME:-$HOME/.local/state}/${serviceName}"
      state_file="$state_dir/status"
      mkdir -p "$state_dir"

      status=""
      if ! status="$(ssh \
        -o BatchMode=yes \
        -o ConnectTimeout=10 \
        -o ServerAliveInterval=5 \
        radon \
        sudo -n uofu-ci-status 2>/dev/null)"; then
        status="''${status:-ssh-unreachable}"
      fi
      previous="$(cat "$state_file" 2>/dev/null || true)"

      if [ "$status" = active ]; then
        rm -f "$state_file"
        exit 0
      fi
      if [ "$status" = "$previous" ]; then
        exit 0
      fi

      printf '%s\n' "$status" >"$state_file"
      case "$status" in
        needs-auth)
          notify-send \
            --urgency=critical \
            --app-name="GitLab Runner" \
            "Radon VPN needs authentication" \
            "Run ‘uofu-runner-vpn renew’ to reconnect the GitLab runner."
          ;;
        unreachable)
          notify-send \
            --urgency=normal \
            --app-name="GitLab Runner" \
            "Radon GitLab endpoint is unreachable" \
            "The VPN is connected, but the private GitLab server did not respond."
          ;;
        misconfigured)
          notify-send \
            --urgency=critical \
            --app-name="GitLab Runner" \
            "Radon GitLab runner is misconfigured" \
            "CI_SERVER_URL is missing or invalid in the runner credential."
          ;;
        ssh-unreachable)
          notify-send \
            --urgency=normal \
            --app-name="GitLab Runner" \
            "Cannot reach Radon’s GitLab runner" \
            "The status check could not connect to Radon over SSH."
          ;;
        *)
          notify-send \
            --urgency=normal \
            --app-name="GitLab Runner" \
            "Cannot check Radon’s GitLab runner" \
            "SSH or the Radon status helper is unavailable."
          ;;
      esac
    '';
  };

  command = pkgs.writeShellApplication {
    name = "uofu-runner-vpn";
    runtimeInputs = [pkgs.gp-saml-gui pkgs.openssh];
    text = ''
      case "''${1:-}" in
        renew)
          echo "Complete the University of Utah login in the local window."
          auth="$(${lib.getExe pkgs.gp-saml-gui} -g --clientos Windows ${vpnServer})"
          eval "$auth"
          : "''${HOST:?Missing VPN host}"
          : "''${USER:?Missing VPN user}"
          : "''${COOKIE:?Missing VPN cookie}"
          : "''${OS:?Missing VPN OS}"
          printf '%s\n%s\n%s\n%s\n' "$HOST" "$USER" "$COOKIE" "$OS" |
            ssh radon sudo -n uofu-ci-submit-auth
          ;;
        status)
          exec ssh radon sudo -n uofu-ci-status
          ;;
        *)
          echo "Usage: uofu-runner-vpn {renew|status}" >&2
          exit 2
          ;;
      esac
    '';
  };
in
  lib.mkIf tokenAvailable {
    home.packages = [command];

    systemd.user.services.${serviceName} = {
      Unit.Description = "Check Radon's University VPN GitLab runner";
      Service = {
        Type = "oneshot";
        ExecStart = lib.getExe monitor;
      };
    };

    systemd.user.timers.${serviceName} = {
      Unit.Description = "Periodically check Radon's University VPN GitLab runner";
      Timer = {
        OnBootSec = "2m";
        OnUnitActiveSec = "5m";
        Persistent = true;
      };
      Install.WantedBy = ["timers.target"];
    };
  }
