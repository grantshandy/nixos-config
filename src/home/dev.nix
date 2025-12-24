{pkgs, ...}: {
  home.packages = with pkgs; [
    # Rust
    rustup
    # rust-analyzer

    # C
    gcc
    # clang-tools
    #
    jetbrains.rust-rover
  ];
}
