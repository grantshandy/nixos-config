{ homeDirectory, username, ... }:
let cameraDir = "${homeDirectory}/Pictures/Camera"; in
let notesDir = "${homeDirectory}/Notes"; in
{
  services.syncthing = {
    enable = true;
    openDefaultPorts = true;

    dataDir = "${homeDirectory}";
    user = "${username}";

    overrideDevices = true;
    settings.devices."phone" = {
      name = "Phone";
      id = "5IBK4XI-3SBE6A7-JCU7L3E-UB3W45N-SMPSC5C-HDHSVBG-UM6XUI6-HQHUSAA";
    };

    overrideFolders = true;
    settings.folders = {
      notes = {
        enable = true;
        id = "gsnotes";
        label = "Notes";
        path = notesDir;
        devices = [ "phone" ];
      };
      photos = {
        enable = true;
        id = "gsphotos";
        label = "Camera";
        path = cameraDir;
        devices = [ "phone" ];
      };
    };
  };

  home-manager.sharedModules = [{
    gtk.gtk3.bookmarks = [ "file://${notesDir}" "file://${cameraDir}" ];
  }];
}
