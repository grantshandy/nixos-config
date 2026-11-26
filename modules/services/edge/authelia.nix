# The authorizer behind the edge proxy.
#
# `access_control.rules` is generated from the service registry, so the set of
# protected resources can no longer drift from what the edge actually puts
# behind forward-auth: both read `fleet.services.<name>.auth`. Previously this
# list was maintained by hand next to a second, differently-shaped list in the
# edge proxy.
{
  config,
  lib,
  ...
}: let
  services = config.fleet.services;
  dns = config.fleet.identity.homelab.dns;
  authHost = "auth.${dns}";
  authUrl = "https://${authHost}";

  # A subdomain service is protected wholesale; an apex service is protected
  # only under its own path prefix, so it can share the domain with others.
  ruleFor = service:
    {
      domain = service.fqdn;
      policy = "two_factor";
    }
    // lib.optionalAttrs (service.subdomain == null) {
      resources =
        if service.path == "/"
        then ["^/$"]
        else ["^${lib.escapeRegex service.basePath}(/.*)?$"];
    };

  accessRules =
    services
    |> lib.attrValues
    |> lib.filter (service: service.public && service.auth != "none")
    |> map ruleFor;
in {
  fleet.aspects.edge-auth.tags = ["edge"];

  flake.modules.nixos.edge-auth = {config, ...}: let
    autheliaUser = config.services.authelia.instances.main.user;
    autheliaGroup = config.services.authelia.instances.main.group;
    secret = name: {
      file = ../../../secrets/${name}.age;
      owner = autheliaUser;
      group = autheliaGroup;
    };
  in {
    age.secrets = {
      authelia-jwt-secret = secret "authelia-jwt-secret";
      authelia-storage-encryption-key = secret "authelia-storage-encryption-key";
      authelia-oidc-hmac-secret = secret "authelia-oidc-hmac-secret";
      authelia-oidc-private-key = secret "authelia-oidc-private-key";
      authelia-users = secret "authelia-users";
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
          rules = accessRules;
        };

        session = {
          expiration = "1 hour";
          inactivity = "10 minutes";
          remember_me = "1 month";
          cookies = [
            {
              domain = dns;
              authelia_url = authUrl;
              default_redirection_url = "https://${services.Headplane.fqdn}";
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
              "${services.Immich.url}auth/login"
              "${services.Immich.url}user-settings"
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

    # Authelia fronts itself; it is the authorizer, not an authorized service,
    # so it is deliberately absent from the registry.
    services.caddy.virtualHosts.${authHost}.extraConfig = ''
      reverse_proxy 127.0.0.1:9091 {
        header_up X-Forwarded-Proto https
      }
    '';
  };
}
