{pkgs, ...}: {
  home.packages = with pkgs; [
    ascii
    man-pages
    alejandra
  ];
}
