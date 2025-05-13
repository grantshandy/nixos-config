{ pkgs, ... }:
let
  lss = pkgs.rustPlatform.buildRustPackage rec {
    pname = "lss";
    version = "1.0.0";

    src = pkgs.fetchFromGitHub {
      owner = "grantshandy";
      repo = "lss";
      rev = version;
      hash = "sha256-yz42y1cC5tPN0s9gf+hEhZP3lYPJLy1lk5ttaBddf4A=";
    };

    useFetchCargoVendor = true;
    cargoHash = "sha256-GJ0bVkUUfB2lQo4p1B2Ac68hobfAVjx7YRicg/1GN+Q=";
  };

  config = {
    port = 9321;
    default = "duckduckgo";

    engines = {
      hmgr = "https://home-manager-options.extranix.com/?query={s}&release=master";
    };
  };

  configFile = (pkgs.formats.toml { }).generate "config.toml" config;
in
{
  home-manager.sharedModules = [{
    systemd.user = {
      enable = true;
      services.lss = {
        Unit = {
          Description = "Search Shortcuts";
          After = [ "network.target" ];
        };
        Path = {
          PathChanged = "${configFile}";
          UnitSec= "1s";
        };
        Service = {
          ExecStart = "${lss}/bin/lss";
          Restart = "always";
        };
        Install.WantedBy = [ "default.target" ];
      };
    };

    xdg.configFile."lss/config.toml".source = configFile;

    programs.firefox.profiles.default.search = {
      force = true;
      default = config.default;
      privateDefault = config.default;
      engines.${config.default}.urls = [{
        template = "http://localhost:${toString (config.port)}/?q={searchTerms}";
      }];
    };
  }];
}
