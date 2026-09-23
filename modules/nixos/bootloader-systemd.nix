{...}: {
  boot.loader = {
    systemd-boot = {
      enable = true;
      configurationLimit = 1;
    };
    efi.canTouchEfiVariables = true;
  };
}
