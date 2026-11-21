{
  helium = {
    system = "x86_64-linux";
    ssh = {
      enable = true;
      port = 4321;
    };
    tailscale.enable = true;
    buildCluster = {
      cache.provide = {
        enable = true;
        priority = 30;
      };
      builders.use = {
        enable = true;
        providers = ["xenon"];
        localJobs = 1;
      };
    };
  };
  xenon = {
    system = "x86_64-linux";
    ssh = {
      enable = true;
      port = 4321;
    };
    tailscale.enable = true;
    buildCluster = {
      cache.provide = {
        enable = true;
        priority = 20;
      };
      builders.provide = {
        enable = true;
        maxJobs = 3;
        speedFactor = 100;
      };
    };
    publicWebServices.OpenWebUI = {
      title = "Open WebUI";
      description = "Local AI chat and coding assistant";
      subdomain = "chat";
      port = 8080;
    };
  };
  krypton = {
    system = "x86_64-linux";
    homeManager.enable = false;
    ssh = {
      enable = true;
      port = 22;
    };
    tailscale = {
      enable = true;
      ipv4 = "100.64.0.3";
    };
    buildCluster.builders.use = {
      enable = true;
      providers = ["radon"];
      localJobs = 0;
    };
    publicWebServices.Headplane = {
      description = "Tailnet administration";
      subdomain = "headplane";
    };
  };
  radon = {
    system = "x86_64-linux";
    ssh = {
      enable = true;
      port = 22;
    };
    tailscale.enable = true;
    buildCluster = {
      cache.provide = {
        enable = true;
        priority = 10;
      };
      builders.provide = {
        enable = true;
        maxJobs = 1;
        speedFactor = 50;
      };
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
      Lidarr = {
        description = "Music collection management";
        path = "/lidarr/";
      };
    };
  };
}
