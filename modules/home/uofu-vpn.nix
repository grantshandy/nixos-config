{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.services.uofu-vpn;
  serviceName = "uofu-vpn";

  command = pkgs.writeShellApplication {
    name = serviceName;
    runtimeInputs = [pkgs.systemd];
    text = ''
      case "''${1:-}" in
        start)
          systemctl --user start ${serviceName}.service
          ;;
        stop)
          systemctl --user stop ${serviceName}.service
          ;;
        status)
          state="$(systemctl --user is-active ${serviceName}.service || true)"
          printf '%s.service is %s\n' ${serviceName} "$state"
          exec journalctl --user --unit ${serviceName}.service --pager-end
          ;;
        *)
          echo "Usage: ${serviceName} {start|stop|status}" >&2
          exit 2
          ;;
      esac
    '';
  };

  gui = pkgs.writeShellApplication {
    name = "${serviceName}-gui";
    runtimeInputs = [pkgs.systemd pkgs.zenity];
    text = ''
      state="$(systemctl --user is-active ${serviceName}.service || true)"

      if [ "$state" = "inactive" ] || [ "$state" = "failed" ]; then
        text="Status: disconnected"
        action="Connect"
        icon="network-vpn-disabled-symbolic"
      else
        text="Status: $state"
        action="Disconnect"
        icon="network-vpn-symbolic"
      fi

      # OK button = toggle the VPN, Cancel button = just close the window.
      if zenity --question \
          --title "University of Utah VPN" \
          --text "$text" \
          --icon "$icon" \
          --ok-label "$action" \
          --cancel-label "Close" \
          --width 300; then
        if [ "$action" = "Connect" ]; then
          systemctl --user start ${serviceName}.service
        else
          systemctl --user stop ${serviceName}.service
        fi
      fi
    '';
  };
in {
  options.services.uofu-vpn = {
    enable = lib.mkEnableOption "University of Utah GlobalProtect VPN helper";

    server = lib.mkOption {
      type = lib.types.str;
      default = "vpn.utah.edu";
      description = "GlobalProtect gateway to connect to.";
    };
  };

  config = lib.mkIf cfg.enable {
    home.packages = [command gui];

    xdg.desktopEntries.${serviceName} = {
      name = "University of Utah VPN";
      comment = "Connect or disconnect the University of Utah VPN";
      exec = lib.getExe gui;
      icon = "network-vpn";
      terminal = false;
      categories = ["Network"];
    };

    systemd.user.services.${serviceName} = {
      Unit = {
        Description = "University of Utah GlobalProtect VPN";
        After = ["graphical-session.target" "network-online.target"];
      };

      Service = {
        ExecStart = "${lib.getExe pkgs.gp-saml-gui} -P -g --clientos Windows ${lib.escapeShellArg cfg.server} -- --protocol=gp";
        KillMode = "control-group";
      };
    };
  };
}
