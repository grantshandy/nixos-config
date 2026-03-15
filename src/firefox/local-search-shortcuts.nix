# home-manager module that automatically enables local-search-shortcuts.
{
  config,
  lib,
  pkgs,
  ...
}: let
  name = "local-search-shortcuts";
  package = pkgs.rustPlatform.buildRustPackage rec {
    pname = name;
    version = "1.2.2";

    src = pkgs.fetchFromGitHub {
      owner = "grantshandy";
      repo = name;
      rev = version;
      hash = "sha256-6uHQ1VkZWtOmY2Q8dgR1if4toMa/czDujaCj65sq498=";
    };

    cargoHash = "sha256-AzhjOoiWWmKzG+/CrN/DUwOERHR1MB2iHzNYM4BJLDA=";
    meta.mainProgram = name;
  };

  cfg = config.services.${name};
  tomlFormat = pkgs.formats.toml {};
  configFile = tomlFormat.generate "${name}-config.toml" cfg.settings;
in {
  options.services.${name} = {
    enable = lib.mkEnableOption name;
    firefoxSearch = lib.mkEnableOption "Set the ${name} provider as the default search engine in Firefox.";
    settings = lib.mkOption {
      type = tomlFormat.type;
      default = {
        port = 9321;
        default = "ddg";
      };
      example = lib.literalExpression ''
        {
          port = 9321;
          default = "ddg";
          engines.homemanager = "https://home-manager-options.extranix.com/?query={s}&release=master";
        }
      '';
    };
    displayName = lib.mkOption {
      type = lib.types.str;
      default = "lss";
    };
  };

  config = lib.mkIf cfg.enable {
    xdg.configFile."${name}/config.toml".source = configFile;

    systemd.user.services.${name} = {
      Unit = {
        Description = "Local Search Shortcuts";
        After = ["network.target"];
        X-Restart-Triggers = [
          configFile
        ];
      };
      Service = {
        ExecStart = lib.getExe package;
        Restart = "always";
      };
      Install.WantedBy = ["default.target"];
    };

    programs.firefox.profiles.default.search = let
      port = toString cfg.settings.port or 9321;
    in
      lib.mkIf cfg.firefoxSearch
      {
        force = true;
        default = cfg.displayName;
        privateDefault = cfg.displayName;
        engines.${cfg.displayName}.urls = [
          {
            template = "http://localhost:${port}/";
            params = [
              {
                name = "q";
                value = "{searchTerms}";
              }
            ];
          }
        ];
      };
  };
}
