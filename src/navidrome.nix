{
  userConfig,
  pkgs,
  ...
}: let
  musicDir = "/media/music";
in {
  ##############################################################
  ## Shared Media Group & Permissions
  ##############################################################
  users.groups.media = {};
  users.users.navidrome.extraGroups = ["media"];
  users.users.${userConfig.user.name}.extraGroups = ["media"];

  # Declarative permissions handled entirely by NixOS
  systemd.tmpfiles.rules = [
    "d /media 0755 root root - -"
    "d ${musicDir} 2775 navidrome media - -"
    "d ${musicDir}/.beets 2775 navidrome media - -"
    "A+ ${musicDir} - - - - group:media:rwx,default:group:media:rwx"
  ];

  services.tailscale.enable = true;
  networking.firewall.trustedInterfaces = ["tailscale0"];

  services.navidrome = {
    enable = true;
    settings = {
      MusicFolder = musicDir;
      Address = "0.0.0.0";
      Scanner.PurgeMissing = "always";
    };
  };

  environment.systemPackages = [ pkgs.nicotine-plus ];

  home-manager.sharedModules = [
    ({...}: {
      programs.beets = {
        enable = true;
        settings = {
          directory = musicDir;
          library = "${musicDir}/.beets/library.db";

          # Force beets to write imported files with group write access
          permfile = "0664";
          permdir = "0775";

          import = {
            move = true; # move files instead of copying
            write = true; # write corrected tags back into files
          };
          plugins = [ "fetchart" "embedart" "scrub" "discogs" "spotify" ];

          # lyrics = {
          #   auto = true;
          #   sources = [ "lrclib" "genius" "musixmatch" ];
          #   synced = true;
          #   force = false;
          # };
        };
      };
    })
  ];
}
