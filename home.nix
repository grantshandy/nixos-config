{ pkgs, username, ... }: {
  home.username = "${username}";
  home.homeDirectory = "/home/${username}";

  programs.helix.enable = true;

  programs.tmux = {
    enable = true;
    escapeTime = 0;
    historyLimit = 100000;
    mouse = true;
  };

  programs.bash = {
    enable = true;
    enableCompletion = true;
  };

  programs.direnv = {
    enable = true;
    nix-direnv.enable = true;
    config = {
      global.load_dotenv = true;
    };
  }; 

  programs.git = {
    enable = true;
    userName = "grantshandy";
    userEmail = "granthandy@proton.me";
  };

  programs.gh = {
    enable = true;
    settings = {
      git_protocol = "https";
      editor = "hx";
    };
  };

  # home-manager expects a valid stateVersion despite following unstable.
  home.stateVersion = "23.11";
  programs.home-manager.enable = true;
}
