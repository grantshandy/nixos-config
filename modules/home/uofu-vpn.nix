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
    home.packages = [command];

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
