{
  lib,
  pkgs,
  pkgs-unstable,
  ...
}: {
  dconf.settings."org/gnome/shell".favorite-apps = ["dev.zed.Zed.desktop"];

  programs.zed-editor = {
    enable = true;
    package = pkgs-unstable.zed-editor;
    extraPackages = with pkgs; [clang-tools];

    extensions = [
      "nix"
      "env"

      "html"
      "html-snippets"
      "svelte"

      "toml"
      "make"
      "typst"
    ];

    themes.adwaita = ./adwaita.json;
    userSettings.theme = {
      mode = "system";
      light = "Adwaita Pastel Light 48";
      dark = "Adwaita Pastel Dark 48";
    };

    userSettings = {
      # disable_ai = true;
      vim_mode = true;
      relative_line_numbers = "enabled";
      git.inline_blame.enabled = false;
      notification_panel.button = false;
      collaboration_panel.button = false;

      title_bar = {
        show_sign_in = false;
        show_user_picture = false;
        show_onboarding_banner = false;
        show_branch_icon = true;
      };

      language_overrides = {
        c.lsp = "clangd";
        cpp.lsp = "clangd";
      };

      languages.Nix = {
        language_servers = ["nixd"];
        formatter.external = {
          command = lib.getExe pkgs.alejandra;
          arguments = ["--quiet" "--"];
        };
      };

      lsp.nixd.binary.path = lib.getExe pkgs.nixd;

      lsp = {
        rust-analyzer = {
          binary.path = lib.getExe pkgs-unstable.rust-analyzer;
          initialization_options = {
            check.command = "clippy";
            command = "clippy";
            rust.analyzerTargetDir = true;
          };
        };

        clangd.binary = {
          path = "${pkgs.clang-tools}/bin/clangd";
          path_lookup = true;
        };

        package-version-server.binary.path = lib.getExe pkgs.package-version-server;
        tinymist.binary.path = lib.getExe pkgs.tinymist;
      };

      dap.CodeLLDB.binary = "${pkgs.vscode-extensions.vadimcn.vscode-lldb}/share/vscode/extensions/vadimcn.vscode-lldb/adapter/codelldb";
    };
  };
}
