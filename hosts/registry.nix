{
  helium = {
    system = "x86_64-linux";
    ssh = {
      enable = true;
      port = 4321;
    };
    tailscale.enable = true;
    cache = {
      enable = true;
      priority = 30;
    };
  };
  xenon = {
    system = "x86_64-linux";
    ssh = {
      enable = true;
      port = 4321;
    };
    tailscale.enable = true;
    cache = {
      enable = true;
      priority = 20;
    };
    privateWebServices.OpenWebUI = {
      title = "Open WebUI";
      description = "Local AI chat";
      port = 8080;
    };
  };
  radon = {
    system = "x86_64-linux";
    ssh = {
      enable = true;
      port = 22;
    };
    tailscale.enable = true;
    cache = {
      enable = true;
      priority = 10;
    };
    publicWebServices = {
      Immich = {
        title = "Photos";
        description = "Immich photo library";
        subdomain = "photos";
        redirectPaths = ["/photos" "/photos/"];
      };
      Navidrome = {
        title = "Music";
        description = "Navidrome music library";
        path = "/music/";
      };
      slskd = {
        description = "Soulseek client";
        path = "/slskd/";
      };
      Cockpit = {
        description = "Server administration";
        subdomain = "cockpit";
      };
      Headplane = {
        description = "Tailnet administration";
        subdomain = "headplane";
      };
      Lidarr = {
        description = "Music collection management";
        path = "/lidarr/";
      };
    };
  };
}
