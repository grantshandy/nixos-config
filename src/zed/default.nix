{pkgs, ...}: {
  home-manager.sharedModules = [
    {
      programs.zed-editor = {
        enable = true;
        extensions = ["nix" "html" "toml" "svelte" "env"];
        themes.adwaita = ./adwaita.json;
        userSettings = {
          languages = {
            Nix = {
              language_servers = ["${pkgs.nixd}/bin/nixd"];
              formatter.external = {
                command = "${pkgs.alejandra}/bin/alejandra";
                arguments = ["--quiet" "--"];
              };
            };
          };
          theme = {
            mode = "system";
            light = "Adwaita Pastel Light 48";
            dark = "Adwaita Pastel Dark 48";
          };
        };
      };
    }
  ];
}
