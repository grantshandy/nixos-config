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
    buildCluster.builders.provide = {
      enable = true;
      maxJobs = 3;
      speedFactor = 100;
    };
    privateWebServices.OpenWebUI = {
      title = "Open WebUI";
      description = "Local AI chat";
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
      ipv4 = "100.64.0.6";
    };
    buildCluster.builders.use = {
      enable = true;
      localJobs = 0;
    };
  };
  radon = {
    system = "x86_64-linux";
    ssh = {
      enable = true;
      port = 22;
    };
    tailscale = {
      enable = true;
      ipv4 = "100.64.0.1";
    };
    buildCluster.builders = {
      provide = {
        enable = true;
        maxJobs = 1;
        speedFactor = 50;
      };
      use = {
        enable = true;
        localJobs = 1;
      };
    };
    virtualMachines.windows-xp = {
      title = "Windows XP";
      kioskClients = ["krypton"];
      vncPort = 5901;
      audioRtpPort = 46000;
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
