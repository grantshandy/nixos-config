{
  lib,
  radonCaddyHost,
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

  services.caddy.virtualHosts.${radonCaddyHost radonEndpoints.Cockpit.host}.extraConfig = ''
    reverse_proxy 127.0.0.1:9090
  '';
}
