{pkgs, ...}: {
  home-manager.sharedModules = [
    {
      programs.zed-editor = {
        enable = true;
        extensions = ["nix" "html" "toml" "svelte" "env"];
        themes.adwaita = ./adwaita.json;
        userSettings = {
          languages.Nix = {
            language_servers = ["${pkgs.nixd}/bin/nixd"];
            formatter.external = {
              command = "${pkgs.alejandra}/bin/alejandra";
              arguments = ["--quiet" "--"];
            };
          };
          lsp = {
            rust-analyzer.binary.path = "${pkgs.rust-analyzer}/bin/rust-analyzer";
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
