{pkgs, ...}: {
  home.packages = with pkgs; [
    cargo
    gcc
  ];
}
