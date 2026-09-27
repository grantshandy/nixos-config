{
  config,
  lib,
  pkgs,
  ...
}: {
  imports = [
    ./hardware-configuration.nix
    ./headscale.nix
    ./music.nix
  ];

  time.timeZone = "America/Denver";

  users.users.${config.identity.user.name} = {
    isNormalUser = true;
    extraGroups = ["wheel"];
    openssh.authorizedKeys.keys = config.identity.ssh.userKeys;
  };
  security.sudo.wheelNeedsPassword = false;

  documentation.enable = false;
  environment.defaultPackages = lib.mkForce [];
  environment.systemPackages = with pkgs; [vim htop git nodejs];

  services.openssh.settings = {
    PasswordAuthentication = lib.mkForce false;
    KbdInteractiveAuthentication = lib.mkForce false;
    PermitRootLogin = lib.mkForce "no";
  };
}
