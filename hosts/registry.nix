{
  helium = {
    system = "x86_64-linux";
    ssh.enable = true;
    ssh.port = 4321;
    tailscale.enable = true;
  };
  xenon = {
    system = "x86_64-linux";
    ssh.enable = true;
    ssh.port = 4321;
    tailscale.enable = true;
  };
  radon = {
    system = "aarch64-linux";
    ssh.enable = true;
    ssh.port = 22;
    tailscale.enable = true;
  };
}
