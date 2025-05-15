{ config, lib, pkgs, ... }:
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

  cfg = config.services.lss;
  tomlFormat = pkgs.formats.toml { };
  configFile = tomlFormat.generate "lss-config.toml" cfg.settings;
in
{
  options.services.lss = {
    enable = lib.mkEnableOption "lss";
    firefoxSearch = lib.mkEnableOption "Set lss as the default search engine in Firefox.";
    settings = lib.mkOption {
      type = tomlFormat.type;
      example = lib.literalExpression ''
        {
          port = 9321;
          default = "duckduckgo";
          engines.homemanager = "https://home-manager-options.extranix.com/?query={s}&release=master";
        }
      '';
    };
  };

  config = lib.mkIf cfg.enable {
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

    programs.firefox.profiles.default.search =
      let
        port = toString cfg.settings.port or 9321;
        name = cfg.settings.default;
        errMsg = "services.lss.settings.default must be set with services.lss.settings.firefoxSearch is enabled";
      in
        lib.mkIf (cfg.firefoxSearch && lib.asserts.assertMsg (lib.attrsets.hasAttr "default" cfg.settings) errMsg)
      {
        force = true;
        default = name;
        privateDefault = name;
        engines.${name}.urls = [{
          inherit name;
          template = "http://localhost:${port}/?q={searchTerms}";
        }];
      };
  };
}
