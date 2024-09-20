{ ... }:
let username = (builtins.fromTOML (builtins.readFile ./config.toml)).user.name; in
{
  services.syncthing = {
    enable = true;
    openDefaultPorts = true;

    dataDir = "/home/${username}/";
    user = "${username}";

    overrideDevices = true;
    settings.devices."phone" = {
      name = "Phone";
      id = "5IBK4XI-3SBE6A7-JCU7L3E-UB3W45N-SMPSC5C-HDHSVBG-UM6XUI6-HQHUSAA";
    };
  };

  home-manager.sharedModules = [{
    gtk.gtk3.bookmarks = [ "file:///home/${username}/Notes" ];
  }];
}
