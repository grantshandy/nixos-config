{ userConfig, pkgs, ... }:
{
  home-manager.sharedModules = [
    {
      programs.helix = {
        enable = true;
        settings = {
          theme = "adwaita-dark";
          editor = {
            bufferline = "multiple";
            auto-format = false;
            lsp.display-messages = true;
            soft-wrap.enable = true;
            indent-guides.render = true;
            statusline = {
              left = [
                "mode"
                "spinner"
              ];
              center = [ "file-name" ];
              right = [
                "diagnostics"
                "selections"
                "position"
                "file-encoding"
                "file-line-ending"
                "file-type"
              ];
              separator = "|";
              mode = {
                normal = "NORMAL";
                insert = "INSERT";
                select = "SELECT";
              };
            };
          };
        };
      };

      programs.neovim = {
        enable = true;
        plugins = [ ];
      };

      programs.tmux = {
        enable = true;

        shortcut = "a";
        escapeTime = 0;

        plugins = [
          pkgs.tmuxPlugins.better-mouse-mode
        ];

        extraConfig = ''
          # https://old.reddit.com/r/tmux/comments/mesrci/tmux_2_doesnt_seem_to_use_256_colors/
          set -g default-terminal "xterm-256color"
          set -ga terminal-overrides ",*256col*:Tc"
          set -ga terminal-overrides '*:Ss=\E[%p1%d q:Se=\E[ q'
          set-environment -g COLORTERM "truecolor"

          # Mouse works as expected
          set-option -g mouse on
          # easy-to-remember split pane commands
          bind | split-window -h -c "#{pane_current_path}"
          bind - split-window -v -c "#{pane_current_path}"
          bind c new-window -c "#{pane_current_path}"
        '';
      };

      programs.bash = {
        enable = true;
        enableCompletion = true;
      };

      programs.direnv = {
        enable = true;
        nix-direnv.enable = true;
        config.global.load_dotenv = true;
      };

      programs.git = {
        enable = true;
        userName = userConfig.git.username;
        userEmail = userConfig.git.email;
      };

      programs.gh = {
        enable = true;
        settings.git_protocol = "https";
      };
    }
  ];
}
