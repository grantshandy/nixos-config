{
  pkgs,
  config,
  ...
}: {
  home-manager.sharedModules = [
    {
      dconf.settings."org/gnome/shell".favorite-apps = ["dev.zed.Zed.desktop"];

      programs.zed-editor = {
        enable = true;
        extensions = ["nix" "html" "toml" "svelte" "env"];
        themes.adwaita = ./adwaita.json;

        extraPackages = with pkgs; [clang-tools];

        userSettings = {
          language_overrides = {
            c.lsp = "clangd";
            cpp.lsp = "clangd";
          };

          languages.Nix = {
            language_servers = ["${pkgs.nixd}/bin/nixd"];
            formatter.external = {
              command = "${pkgs.alejandra}/bin/alejandra";
              arguments = ["--quiet" "--"];
            };
          };
          lsp = {
            rust-analyzer.binary.path = "${pkgs.rust-analyzer}/bin/rust-analyzer";

            clangd = {
              binary = {
                path = "${pkgs.clang-tools}/bin/clangd";
                path_lookup = true;
              };
            };
          };
          theme = {
            mode = "system";
            light = "Adwaita Pastel Light 48";
            dark = "Adwaita Pastel Dark 48";
          };
          features.edit_prediction_provider = "supermaven";
        };
      };
    }
  ];
}
