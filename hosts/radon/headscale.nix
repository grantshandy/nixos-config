{
  config,
  pkgs,
  pkgs-unstable,
  lib,
  ...
}: let
  dns = config.identity.homelab.dns;
  base_url = "https://${dns}";
  secrets_dir = "/var/secrets";
  headscale_key_path = "${secrets_dir}/headscale_api_key";
  headplane_cookie_path = "${secrets_dir}/headplane_cookie_secret";
  headplane_agent_authkey_path = "${secrets_dir}/headplane_agent_authkey";
  server_authkey_path = "${secrets_dir}/tailscale_authkey";
  headplane_port = 8000;
  headscale_port = 8080;
in {
  networking = {
    hosts = {
      "127.0.0.1" = [dns];
    };
    firewall = {
      allowedTCPPorts = [443 headplane_port];
      interfaces.tailscale0.allowedTCPPorts = [headplane_port];
    };
  };

  services.tailscale.authKeyFile = server_authkey_path;

  systemd.services.tailscaled-autoconnect = {
    after = ["headplane-secrets.service" "caddy.service"];
    requires = ["headplane-secrets.service"];
  };

  services.caddy = {
    enable = true;
    globalConfig = ''
      auto_https disable_redirects
    '';
    virtualHosts.${dns}.extraConfig = ''
      handle /music* {
        reverse_proxy http://xenon:4533
      }
      handle {
        reverse_proxy 127.0.0.1:${toString headscale_port}
      }
    '';
  };

  services.duckdns = {
    enable = true;
    domains = [(lib.head (lib.splitString "." dns))];
    tokenFile = ./duckdns-token.txt;
  };

  services.headscale = {
    enable = true;
    package = pkgs-unstable.headscale;
    port = headscale_port;
    address = "127.0.0.1";

    settings = {
      server_url = base_url;

      dns = {
        magic_dns = true;
        base_domain = "ts.${dns}";
        nameservers.global = ["1.1.1.1"];
      };

      database = {
        type = "sqlite";
        sqlite = {
          path = "/var/lib/headscale/db.sqlite";
          write_ahead_log = true;
        };
      };
    };
  };

  services.headplane = {
    enable = true;
    package = pkgs-unstable.headplane;
    settings = {
      server = {
        host = "0.0.0.0";
        port = headplane_port;
        cookie_secure = false;
        cookie_secret_path = headplane_cookie_path;
      };

      headscale.url = "http://127.0.0.1:${toString headscale_port}";

      integration.agent = {
        enabled = true;
        host_name = "headplane-agent";
        pre_authkey_path = headplane_agent_authkey_path;
      };
    };
  };

  systemd.tmpfiles.rules = [
    "d ${secrets_dir} 0700 ${config.services.headscale.user} ${config.services.headscale.group} -"
  ];

  systemd.services.headplane-secrets = {
    description = "Generate Headplane Secrets on First Boot";
    after = ["headscale.service"];
    requires = ["headscale.service"];
    before = ["headplane.service"];
    requiredBy = ["headplane.service"];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      hs=${lib.getExe config.services.headscale.package}
      jq=${lib.getExe pkgs.jq}

      mkdir -p ${secrets_dir}
      chmod 700 ${secrets_dir}

      if [ ! -f ${headplane_cookie_path} ]; then
        ${pkgs.coreutils}/bin/tr -dc A-Za-z0-9 </dev/urandom | ${pkgs.coreutils}/bin/head -c 32 > ${headplane_cookie_path}
      fi

      # Wait for headscale's CLI socket (replaces the fixed `sleep 3`)
      for _ in $(seq 1 30); do
        "$hs" users list >/dev/null 2>&1 && break
        sleep 1
      done

      default_user_id() {
        "$hs" users list -o json | "$jq" -r '.[]? | select(.name == "default") | .id'
      }

      if [ -z "$(default_user_id)" ]; then
        "$hs" users create default
      fi

      if [ ! -f ${headscale_key_path} ]; then
        "$hs" apikeys create --expiration 3650d > ${headscale_key_path}
      fi

      # Reusable key so the server can re-enroll if /var/lib/tailscale is ever wiped
      if [ ! -f ${server_authkey_path} ]; then
        key=$("$hs" preauthkeys create --user "$(default_user_id)" --reusable --expiration 3650d)
        printf '%s' "$key" > ${server_authkey_path}
      fi

      # Reusable key for the Headplane agent (separate from the server's own key)
      if [ ! -f ${headplane_agent_authkey_path} ]; then
        key=$("$hs" preauthkeys create --user "$(default_user_id)" --reusable --expiration 3650d)
        printf '%s' "$key" > ${headplane_agent_authkey_path}
      fi

      chown -R ${config.services.headscale.user}:${config.services.headscale.group} ${secrets_dir}
      chmod 400 ${secrets_dir}/*
    '';
  };
}
