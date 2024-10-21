{ userConfig, lib, ... }: with userConfig;
{
  services.syncthing = {
    enable = true;
    openDefaultPorts = true;

    dataDir = "/home/${user.name}/";
    user = "${user.name}";

    overrideDevices = true;
    settings.devices = builtins.listToAttrs (map
      (device: with device; { name = lib.toLower name; value = device; })
      sync-device);
  };

  home-manager.sharedModules = [{
    gtk.gtk3.bookmarks = [ "file:///home/${user.name}/Notes" ];
  }];
}
