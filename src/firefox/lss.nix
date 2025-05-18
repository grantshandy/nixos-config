{ config, lib, pkgs, ... }:
let
  lss = pkgs.rustPlatform.buildRustPackage rec {
    pname = "lss";
    version = "1.1.0";

    src = pkgs.fetchFromGitHub {
      owner = "grantshandy";
      repo = "lss";
      rev = version;
      hash = "sha256-tDYnHbbflLpPHx3RN01Zuy6C5uNBcJ7D+bL0lRLTST0=";
    };

    useFetchCargoVendor = true;
    cargoHash = "sha256-U0U+V7aVE/aoeX4ZMzQ6cCsEY2PVjkS4N07bUSwsVMc=";
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
