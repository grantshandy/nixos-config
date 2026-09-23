{pkgs, ...}: {
  environment.systemPackages = [pkgs.nicotine-plus];

  networking.firewall = {
    allowedTCPPorts = [55125 55126];
    allowedUDPPorts = [55125 55126];
  };
}
