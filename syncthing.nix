{ username, ... }: {
  services.syncthing = {
    enable = true;
    dataDir = "/home/${username}";
    openDefaultPorts = true;
    user = "${username}";
    group = "users";

    overrideDevices = true;
    settings.devices."phone" = {
      name = "Phone";
      id = "5IBK4XI-3SBE6A7-JCU7L3E-UB3W45N-SMPSC5C-HDHSVBG-UM6XUI6-HQHUSAA";
    };

    overrideFolders = true;
    settings.folders."notes" = {
      enable = true;
      id = "gsnotes";
      label = "Notes";
      path = "/home/${username}/Notes";
      devices = [ "phone" ];
    };
  };
}
