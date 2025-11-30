{
  userConfig,
  pkgs,
  ...
}: {
  imports = [
    ./nvim.nix
  ];

  programs.home-manager.enable = true;

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

      # vim-like pane resizing
      bind -r C-k resize-pane -U
      bind -r C-j resize-pane -D
      bind -r C-h resize-pane -L
      bind -r C-l resize-pane -R

      # vim-like pane switching
      bind -r k select-pane -U
      bind -r j select-pane -D
      bind -r h select-pane -L
      bind -r l select-pane -R

      # and now unbind keys
      unbind Up
      unbind Down
      unbind Left
      unbind Right

      unbind C-Up
      unbind C-Down
      unbind C-Left
      unbind C-Right
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
    settings.user = userConfig.git;
  };

  programs.gh = {
    enable = true;
    settings.git_protocol = "https";
  };
}
