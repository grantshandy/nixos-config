{
  lib,
  pkgs,
  pkgs-unstable,
  ...
}: {
  desktop.favoriteApps = ["dev.zed.Zed.desktop"];

  programs.zed-editor = {
    enable = true;
    package = pkgs-unstable.zed-editor;
    extraPackages = with pkgs; [clang-tools tinymist package-version-server ruff nodejs];

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
      vim_mode = true;
      relative_line_numbers = "enabled";
      git.inline_blame.enabled = false;
      notification_panel.button = false;
      collaboration_panel.button = true;

      node = {
        path = lib.getExe pkgs.nodejs;
        npm_path = "${pkgs.nodejs}/bin/npm";
      };

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

        # package-version-server.binary.path = lib.getExe pkgs.package-version-server;
        # tinymist.binary.path = lib.getExe pkgs.tinymist;
      };

      agent_servers."Claude" = {
        command = lib.getExe pkgs.claude-agent-acp;
        type = "custom";
      };

      language_models."llama.cpp" = {
        api_url = "http://xenon:8081";
        auto_discover = false;
        available_models = [
          {
            name = "qwen3.6-35b-a3b-q4-k-m";
            display_name = "Qwen 3.6 35B A3B Q4_K_M";
            max_tokens = 65536;
            max_output_tokens = 32768;
            supports_tools = true;
            supports_images = false;
            supports_thinking = true;
          }
        ];
      };

      agent = {
        default_model = {
          provider = "llama.cpp";
          model = "qwen3.6-35b-a3b-q4-k-m";
        };
        auto_compact = {
          enabled = true;
          threshold = "90%";
        };
      };

      dap.CodeLLDB.binary = "${pkgs.vscode-extensions.vadimcn.vscode-lldb}/share/vscode/extensions/vadimcn.vscode-lldb/adapter/codelldb";
    };
  };
}
