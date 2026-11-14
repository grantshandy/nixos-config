{
  inputs,
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
  server_authkey_path = "${secrets_dir}/tailscale_authkey";
  headplane_port = 8000;
  headscale_port = 8080;
  directoryPage = pkgs.writeTextDir "index.html" ''
    <!doctype html>
    <html lang="en">
      <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <title>Radon services</title>
        <style>
          :root {
            color-scheme: light dark;
            font-family: system-ui, -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
            --page: #fafafa;
            --card: #ffffff;
            --card-hover: #f6f5f4;
            --border: #deddda;
            --text: #2e3436;
            --muted: #5e5c64;
            --accent: #3584e4;
            --shadow: 0 2px 6px rgb(0 0 0 / 12%);
          }
          * { box-sizing: border-box; }
          body {
            min-height: 100vh;
            max-width: 56rem;
            margin: 0 auto;
            padding: clamp(3rem, 10vh, 6rem) 1.5rem;
            background: var(--page);
            color: var(--text);
          }
          h1 { margin: 0; font-size: 2rem; line-height: 1.2; letter-spacing: -.02em; }
          p { margin: .5rem 0 0; color: var(--muted); }
          ul {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(14rem, 1fr));
            gap: 1rem;
            padding: 0;
            margin: 2rem 0 0;
            list-style: none;
          }
          a {
            display: block;
            min-height: 7rem;
            padding: 1.25rem;
            border: 1px solid var(--border);
            border-radius: 12px;
            background: var(--card);
            box-shadow: var(--shadow);
            color: var(--text);
            text-decoration: none;
            transition: background-color 120ms ease, border-color 120ms ease, transform 120ms ease;
          }
          a:hover { border-color: var(--accent); background: var(--card-hover); transform: translateY(-1px); }
          a:active { transform: translateY(0); }
          a:focus-visible { outline: 2px solid var(--accent); outline-offset: 3px; }
          strong, span { display: block; }
          strong { font-size: 1.05rem; font-weight: 700; }
          span { margin-top: .45rem; font-size: .9rem; line-height: 1.4; color: var(--muted); }
          @media (prefers-color-scheme: dark) {
            :root {
              --page: #303030;
              --card: #3b3b3b;
              --card-hover: #424242;
              --border: #555555;
              --text: #ffffff;
              --muted: #deddda;
              --accent: #62a0ea;
              --shadow: 0 2px 6px rgb(0 0 0 / 35%);
            }
          }
          @media (prefers-reduced-motion: reduce) { a { transition: none; } }
        </style>
      </head>
      <body>
        <h1>The Inner Circle</h1>
        <ul>
          <li><a href="https://headplane.${dns}/"><strong>Headplane</strong><span>Tailnet administration</span></a></li>
          <li><a href="https://cockpit.${dns}/"><strong>Cockpit</strong><span>Server administration</span></a></li>
          <li><a href="https://photos.${dns}/"><strong>Photos</strong><span>Immich photo library</span></a></li>
          <li><a href="https://${dns}/music/"><strong>Music</strong><span>Navidrome music library</span></a></li>
          <li><a href="https://${dns}/lidarr/"><strong>Lidarr</strong><span>Music collection management</span></a></li>
          <li><a href="https://${dns}/slskd/"><strong>slskd</strong><span>Soulseek client</span></a></li>
        </ul>
      </body>
    </html>
  '';
in {
  disabledModules = [
    "services/networking/headscale.nix"
    "services/networking/headplane.nix"
  ];
  imports = [
    "${inputs.nixpkgs-unstable}/nixos/modules/services/networking/headscale.nix"
    "${inputs.nixpkgs-unstable}/nixos/modules/services/networking/headplane.nix"
  ];

  networking = {
    hosts = {
      "127.0.0.1" = [dns];
    };
    firewall.allowedTCPPorts = [443];
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
      handle / {
        forward_auth 127.0.0.1:9091 {
          uri /api/authz/forward-auth
          copy_headers Remote-User Remote-Groups Remote-Email Remote-Name
        }
        root * ${directoryPage}
        file_server
      }

      handle {
        reverse_proxy 127.0.0.1:${toString headscale_port}
      }
    '';
  };

  services.duckdns = {
    enable = true;
    domains = [(lib.head (lib.splitString "." dns))];
    tokenFile = config.age.secrets.duckdns-token.path;
  };

  age.secrets.duckdns-token.file = ../../secrets/duckdns-token.age;

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
    agent.package = pkgs-unstable.headplane-agent;
    settings = {
      headscale = {
        url = "http://127.0.0.1:${toString headscale_port}";
        api_key_path = headscale_key_path;
      };

      server = {
        host = "127.0.0.1";
        port = headplane_port;
        cookie_secure = true;
        cookie_secret_path = headplane_cookie_path;
        proxy_auth = {
          enabled = true;
          user_header = "Remote-User";
          email_header = "Remote-Email";
          name_header = "Remote-Name";
          allowed_cidrs = ["127.0.0.1/32"];
        };
      };
      integration.agent = {
        enabled = true;
        host_name = "headplane-agent";
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

      chown -R ${config.services.headscale.user}:${config.services.headscale.group} ${secrets_dir}
      chmod 400 ${secrets_dir}/*
    '';
  };
}
