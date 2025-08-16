{pkgs, ...}: {
  programs.nixvim = {
    enable = true;
    defaultEditor = true;
    nixpkgs.useGlobalPackages = true;

    plugins = {
      telescope.enable = true;
      neo-tree.enable = true;
      autoclose.enable = true;

      treesitter.enable = true;

      rustaceanvim = {
        enable = true;
        settings = {
          tools.enable_clippy = true;

          server.default_settings = {
            inlayHints = {lifetimeElisionHints = {enable = "always";};};
            rust-analyzer = {
              cargo.allFeatures = true;
              check.command = "clippy";
              files.excludeDirs = ["target" ".git" ".cargo" ".github" ".direnv"];
            };
          };
        };
      };

      lsp = {
        enable = true;
      };
    };

    keymaps = [
      {
        mode = "n";
        key = "<leader>e";
        action = "<CMD>Neotree toggle<CR>";
        options.desc = "NeoTree";
      }

      # Files
      {
        mode = "n";
        key = "<leader>ff";
        action = "<CMD>Telescope find_files<CR>";
        options.desc = "Find files";
      }

      # Buffers
      {
        mode = "n";
        key = "<leader>fb";
        action = "<CMD>Telescope buffers<CR>";
        options.desc = "Find buffers";
      }

      # Live Grep (search for a string in your project)
      {
        mode = "n";
        key = "<leader>fg";
        action = "<CMD>Telescope live_grep<CR>";
        options.desc = "Live Grep";
      }

      # Help Tags (search for help documentation)
      {
        mode = "n";
        key = "<leader>fh";
        action = "<CMD>Telescope help_tags<CR>";
        options.desc = "Find help tags";
      }
    ];
  };

  environment.systemPackages = with pkgs; [ripgrep];
}
