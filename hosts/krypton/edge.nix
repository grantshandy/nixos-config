{
  config,
  lib,
  ...
}: let
  dns = config.identity.homelab.dns;
  auth = ''
    forward_auth 127.0.0.1:9091 {
      uri /api/authz/forward-auth
      header_up X-Forwarded-Proto https
      copy_headers Remote-User Remote-Groups Remote-Email Remote-Name
    }
  '';
  backendAuth = ''
    forward_auth 127.0.0.1:9091 {
      uri /api/authz/forward-auth
      header_up X-Forwarded-Proto https
      # API credentials belong to the backend, not the authorization subrequest.
      # These changes affect only the cloned forward-auth request.
      header_up -Authorization
      header_up -X-Api-Key
      header_up X-Forwarded-URI {http.request.uri.path}
      copy_headers Remote-User Remote-Groups Remote-Email Remote-Name
    }
  '';
  radonCaddy = "http://radon.ts.${dns}:8080";
  radonServices = config.network.hosts.radon.publicWebServices;
  radonEndpoints = lib.mapAttrs (_: service: let
    host = "${lib.optionalString (service.subdomain != null) "${service.subdomain}."}${dns}";
  in
    service
    // {
      inherit host;
      url = "https://${host}${service.path}";
      basePath = lib.removeSuffix "/" service.path;
    })
  radonServices;

  radonSubdomainVirtualHosts =
    radonEndpoints
    |> lib.filterAttrs (_: service: service.subdomain != null)
    |> lib.mapAttrs' (name: service:
      lib.nameValuePair service.host {
        extraConfig = ''
          ${lib.optionalString (name == "Cockpit") backendAuth}
          reverse_proxy ${radonCaddy}
        '';
      });

  apexPathsFor = service:
    service.redirectPaths
    ++ lib.optionals (service.subdomain == null && service.path != "/") (let
      basePath = lib.removeSuffix "/" service.path;
    in [
      basePath
      service.path
      "${basePath}/*"
    ]);
  radonApexPaths =
    radonEndpoints
    |> lib.attrValues
    |> lib.concatMap apexPathsFor
    |> lib.unique;
  protectedApexPaths =
    ["Lidarr" "slskd"]
    |> lib.concatMap (name: apexPathsFor radonEndpoints.${name})
    |> lib.unique;

  openWebui = config.network.hosts.xenon.publicWebServices.OpenWebUI;
  openWebuiHost = "${openWebui.subdomain}.${dns}";
in {
  _module.args = {inherit radonEndpoints;};

  age.secrets.duckdns-token.file = ../../secrets/duckdns-token.age;

  services.duckdns = {
    enable = true;
    domains = [(lib.head (lib.splitString "." dns))];
    tokenFile = config.age.secrets.duckdns-token.path;
  };

  services.caddy = {
    enable = true;
    globalConfig = ''
      auto_https disable_redirects
      acme_ca https://acme-v02.api.letsencrypt.org/directory
      email ${config.identity.git.email}
    '';
    virtualHosts =
      radonSubdomainVirtualHosts
      // {
        ${dns}.extraConfig = lib.mkBefore ''
          @protectedRadon path ${lib.concatStringsSep " " protectedApexPaths}
          handle @protectedRadon {
            ${backendAuth}
            reverse_proxy ${radonCaddy}
          }

          @radon path ${lib.concatStringsSep " " radonApexPaths}
          handle @radon {
            reverse_proxy ${radonCaddy}
          }
        '';

        ${openWebuiHost}.extraConfig = ''
          ${auth}
          reverse_proxy xenon.ts.${dns}:${toString openWebui.port}
        '';
      };
  };

  networking.firewall.allowedTCPPorts = [443];
}
