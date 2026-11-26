{config, ...}: let
  port = 9090;
  service = config.fleet.services.Cockpit;
in {
  fleet.services.Cockpit = {
    host = "radon";
    description = "Server administration";
    subdomain = "cockpit";
    auth = "backend";
    localProxy.port = port;
  };

  flake.modules.nixos.Cockpit = {lib, ...}: {
    services.cockpit = {
      enable = true;
      inherit port;
      openFirewall = false;
      settings.WebService = {
        Origins = lib.mkForce (lib.removeSuffix "/" service.url);
        ProtocolHeader = "X-Forwarded-Proto";
        AllowUnencrypted = true;
      };
    };

    # The host proxy is Cockpit's only network entry point.
    systemd.sockets.cockpit.listenStreams = lib.mkForce [
      ""
      "127.0.0.1:${toString port}"
    ];
  };
}
