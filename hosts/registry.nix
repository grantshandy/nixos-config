{
  helium = {
    system = "x86_64-linux";
    ssh.enable = true;
    ssh.port = 4321;
    tailscale.enable = true;
    cache = {
      enable = true;
      priority = 30;
    };
    firefox.enable = true;
  };
  xenon = {
    system = "x86_64-linux";
    ssh.enable = true;
    ssh.port = 4321;
    tailscale.enable = true;
    cache = {
      enable = true;
      priority = 20;
    };
    firefox.enable = true;
  };
  radon = {
    system = "x86_64-linux";
    ssh.enable = true;
    ssh.port = 22;
    tailscale.enable = true;
    cache = {
      enable = true;
      priority = 10;
    };
    webServices = {
      Immich.subdomain = "photos";
      Navidrome.path = "/music/";
      slskd.path = "/slskd/";
      Cockpit.subdomain = "cockpit";
      Headplane.subdomain = "headplane";
    };
  };
}
