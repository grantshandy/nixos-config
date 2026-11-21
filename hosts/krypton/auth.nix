{
  config,
  lib,
  radonEndpoints,
  ...
}: let
  dns = config.identity.homelab.dns;
  authHost = "auth.${dns}";
  authUrl = "https://${authHost}";
  headplaneHost = "${config.network.hosts.krypton.publicWebServices.Headplane.subdomain}.${dns}";
  headplaneUrl = "https://${headplaneHost}";
  grafanaHost = "${config.network.hosts.krypton.publicWebServices.Grafana.subdomain}.${dns}";
  openWebuiHost = "${config.network.hosts.xenon.publicWebServices.OpenWebUI.subdomain}.${dns}";
  autheliaUser = config.services.authelia.instances.main.user;
  autheliaGroup = config.services.authelia.instances.main.group;
in {
  age.secrets = {
    authelia-jwt-secret = {
      file = ../../secrets/authelia-jwt-secret.age;
      owner = autheliaUser;
      group = autheliaGroup;
    };
    authelia-storage-encryption-key = {
      file = ../../secrets/authelia-storage-encryption-key.age;
      owner = autheliaUser;
      group = autheliaGroup;
    };
    authelia-oidc-hmac-secret = {
      file = ../../secrets/authelia-oidc-hmac-secret.age;
      owner = autheliaUser;
      group = autheliaGroup;
    };
    authelia-oidc-private-key = {
      file = ../../secrets/authelia-oidc-private-key.age;
      owner = autheliaUser;
      group = autheliaGroup;
    };
    authelia-users = {
      file = ../../secrets/authelia-users.age;
      owner = autheliaUser;
      group = autheliaGroup;
    };

  };

  services.authelia.instances.main = {
    enable = true;

    secrets = {
      jwtSecretFile = config.age.secrets.authelia-jwt-secret.path;
      storageEncryptionKeyFile = config.age.secrets.authelia-storage-encryption-key.path;
      oidcHmacSecretFile = config.age.secrets.authelia-oidc-hmac-secret.path;
      oidcIssuerPrivateKeyFile = config.age.secrets.authelia-oidc-private-key.path;
    };

    settings = {
      theme = "auto";
      server.address = "tcp://127.0.0.1:9091/";

      log.level = "info";

      authentication_backend.file = {
        path = config.age.secrets.authelia-users.path;
        watch = false;
      };

      webauthn = {
        disable = false;
        enable_passkey_login = false;
        display_name = authHost;
        attestation_conveyance_preference = "none";
        timeout = "2 minutes";
        selection_criteria = {
          attachment = "";
          discoverability = "preferred";
          user_verification = "required";
        };
      };

      access_control = {
        default_policy = "deny";
        rules = [
          {
            domain = radonEndpoints.Cockpit.host;
            policy = "two_factor";
          }
          {
            domain = headplaneHost;
            policy = "two_factor";
          }
          {
            domain = grafanaHost;
            policy = "two_factor";
          }
          {
            domain = openWebuiHost;
            policy = "two_factor";
          }
          {
            domain = dns;
            resources = ["^/$"];
            policy = "two_factor";
          }
          {
            domain = radonEndpoints.Lidarr.host;
            resources = ["^${lib.escapeRegex radonEndpoints.Lidarr.basePath}(/.*)?$"];
            policy = "two_factor";
          }
          {
            domain = radonEndpoints.slskd.host;
            resources = ["^${lib.escapeRegex radonEndpoints.slskd.basePath}(/.*)?$"];
            policy = "two_factor";
          }
        ];
      };

      session = {
        expiration = "1 hour";
        inactivity = "10 minutes";
        remember_me = "1 month";
        cookies = [
          {
            domain = dns;
            authelia_url = authUrl;
            default_redirection_url = headplaneUrl;
            same_site = "lax";
          }
        ];
      };

      regulation = {
        max_retries = 5;
        find_time = "2 minutes";
        ban_time = "15 minutes";
      };

      storage.local.path = "/var/lib/authelia-main/db.sqlite3";
      notifier.filesystem.filename = "/var/lib/authelia-main/notification.txt";

      identity_providers.oidc.clients = [
        {
          client_id = "immich";
          client_name = "Immich";
          client_secret = "$pbkdf2-sha512$310000$pd8H5vwuC7EW1l89A2UcTQ$ocdsq0KPs3dM/h04tg4wqM/vR3u.6pXb3qOHIx13UD6yKM8lV1QsJUWv179cNf.nfVE9uu0bIuNj8V64.FZxOg";
          public = false;
          authorization_policy = "two_factor";
          require_pkce = true;
          pkce_challenge_method = "S256";
          redirect_uris = [
            "${radonEndpoints.Immich.url}auth/login"
            "${radonEndpoints.Immich.url}user-settings"
            "app.immich:///oauth-callback"
          ];
          scopes = [
            "openid"
            "profile"
            "email"
          ];
          response_types = ["code"];
          grant_types = ["authorization_code"];
          id_token_signed_response_alg = "RS256";
          userinfo_signed_response_alg = "none";
          token_endpoint_auth_method = "client_secret_post";
        }
      ];
    };
  };

  services.caddy.virtualHosts.${authHost}.extraConfig = ''
    reverse_proxy 127.0.0.1:9091 {
      header_up X-Forwarded-Proto https
    }
  '';
}
