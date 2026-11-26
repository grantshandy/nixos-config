# The service registry.
#
# One entry per network service, declared by the module that *implements* it.
# Everything derivable is derived here exactly once -- previously `fqdn`/`url`/
# `basePath` were recomputed by four separate callers, and per-service policy was
# spelled out again in the edge proxy, in Authelia, and in the directory page.
#
# Declaring `host` is also what enrolls the service's aspect onto that machine,
# so a new service means one new file and no import lists to update.
{
  config,
  lib,
  ...
}: let
  inherit (lib) mkOption types;
  dns = config.fleet.identity.homelab.dns;
in {
  options.fleet.services = mkOption {
    default = {};
    description = "Network services offered by the fleet, keyed by service name.";
    type = types.attrsOf (types.submodule ({name, ...} @ svc: {
      options = {
        name = mkOption {
          type = types.str;
          default = name;
          internal = true;
        };

        host = mkOption {
          type = types.str;
          description = "Registry host name of the machine that runs this service.";
        };

        title = mkOption {
          type = types.str;
          default = name;
          description = "Human-readable service name used for bookmarks and the directory.";
        };

        description = mkOption {
          type = types.str;
          default = "";
          description = "Description displayed in the service directory.";
        };

        subdomain = mkOption {
          type = types.nullOr types.str;
          default = null;
          description = "Subdomain relative to identity.homelab.dns, or null for the apex domain.";
        };

        path = mkOption {
          type = types.str;
          default = "/";
          description = "Absolute URL path for the service.";
        };

        port = mkOption {
          type = types.nullOr types.port;
          default = null;
          description = "Backend port the service listens on.";
        };

        public = mkOption {
          type = types.bool;
          default = true;
          description = "Whether the edge publishes this service outside the tailnet.";
        };

        auth = mkOption {
          type = types.enum ["none" "session" "backend"];
          default = "session";
          description = ''
            Authelia policy applied at the edge.

            - "none": no forward-auth; the service does its own authentication.
            - "session": plain forward-auth, for browser-only services.
            - "backend": forward-auth that strips Authorization and X-Api-Key
              from the authorization subrequest, for services whose own API
              credentials must reach the backend untouched.

            Anything other than "none" also generates an Authelia access_control
            rule, so the edge and the authorizer can no longer disagree.
          '';
        };

        upstream = mkOption {
          type = types.enum ["host-proxy" "direct"];
          default = "host-proxy";
          description = ''
            How the edge reaches this service: via the owning host's local
            reverse proxy, or straight to `port` over the tailnet.
          '';
        };

        localProxy.port = mkOption {
          type = types.nullOr types.port;
          default = null;
          description = "Port the owning host's local proxy should forward to, if it fronts this service.";
        };

        localProxy.extraConfig = mkOption {
          type = types.lines;
          default = "";
          description = ''
            Caddy directives inserted into the owning host's local proxy ahead of
            this service's catch-all handler, for the rare service that needs a
            sibling path served by something else.
          '';
        };

        redirectPaths = mkOption {
          type = types.listOf types.str;
          default = [];
          description = "Extra apex-domain paths routed to this service.";
        };

        directory = mkOption {
          type = types.bool;
          default = true;
          description = "Whether to list this service on the homelab directory page.";
        };

        bookmark = mkOption {
          type = types.bool;
          default = true;
          description = "Whether to include this service in Firefox bookmarks.";
        };

        # Derived, so no consumer re-implements them.
        fqdn = mkOption {
          type = types.nullOr types.str;
          readOnly = true;
        };
        url = mkOption {
          type = types.nullOr types.str;
          readOnly = true;
        };
        basePath = mkOption {
          type = types.str;
          readOnly = true;
          description = "`path` without its trailing slash; the empty string for the apex root.";
        };
        apexPaths = mkOption {
          type = types.listOf types.str;
          readOnly = true;
          description = "Apex-domain path matchers the edge must route to this service.";
        };
        tailnetUrl = mkOption {
          type = types.nullOr types.str;
          readOnly = true;
          description = "Direct HTTP URL over Tailscale, or null when the service has no port.";
        };
      };

      config = let
        self = svc.config;
      in {
        fqdn =
          if self.public
          then "${lib.optionalString (self.subdomain != null) "${self.subdomain}."}${dns}"
          else null;
        url =
          if self.public
          then "https://${self.fqdn}${self.path}"
          else null;
        basePath = lib.removeSuffix "/" self.path;
        tailnetUrl =
          if self.port == null
          then null
          else "http://${self.host}.ts.${dns}:${toString self.port}${self.basePath}";
        auth = lib.mkDefault (
          if self.public
          then "session"
          else "none"
        );
        directory = lib.mkDefault self.public;
        bookmark = lib.mkDefault self.public;
        apexPaths = lib.optionals self.public (
          self.redirectPaths
          ++ lib.optionals (self.subdomain == null && self.path != "/") [
            self.basePath
            self.path
            "${self.basePath}/*"
          ]
        );
      };
    }));
  };
}
