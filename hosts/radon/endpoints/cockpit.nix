{
  lib,
  radonEndpoints,
  ...
}: {
  services.cockpit = {
    enable = true;
    port = 9090;
    openFirewall = false;
    settings.WebService = {
      Origins = lib.mkForce (lib.removeSuffix "/" radonEndpoints.Cockpit.url);
      ProtocolHeader = "X-Forwarded-Proto";
      AllowUnencrypted = true;
    };
  };

  # Caddy is Cockpit's only network entry point.
  systemd.sockets.cockpit.listenStreams = lib.mkForce [
    ""
    "127.0.0.1:9090"
  ];

  services.caddy.virtualHosts.${radonEndpoints.Cockpit.host}.extraConfig = ''
    forward_auth 127.0.0.1:9091 {
      uri /api/authz/forward-auth
      header_up -Authorization
      copy_headers Remote-User Remote-Groups Remote-Email Remote-Name
    }
    reverse_proxy 127.0.0.1:9090
  '';
}
