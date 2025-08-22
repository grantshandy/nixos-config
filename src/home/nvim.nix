{
  inputs,
  pkgs,
  ...
}: {
  imports = [
    inputs.nixvim.homeModules.nixvim
  ];

  home.packages = [pkgs.ripgrep];

  # dconf.settings."org/gnome/Ptyxis/Profiles/d6b22da30fc4910e7f570a9f68472f1b" = {
  #   label = "default";
  #   pallete = "Everforest";
  #   use-proxy = false;
  # };

  programs.nixvim = {
    enable = true;
    defaultEditor = true;
    nixpkgs.useGlobalPackages = true;

    colorschemes.ayu.enable = true;

    plugins = {
      lsp.enable = true;

      telescope.enable = true;
      nvim-tree.enable = true;
      autoclose.enable = true;
      treesitter.enable = true;
      transparent.enable = true;

      web-devicons.enable = true;

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
    };

    keymaps = [
      {
        mode = "n";
        key = "<leader>e";
        action = "<CMD>NvimTreeToggle<CR>";
        options.desc = "NvimTree";
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
}
