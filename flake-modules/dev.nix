{inputs, ...}: {
  perSystem = {
    pkgs,
    system,
    ...
  }: {
    formatter = pkgs.alejandra;

    devShells.default = pkgs.mkShell {
      packages = [
        inputs.agenix.packages.${system}.default
        pkgs.alejandra
        pkgs.git
        pkgs.htop
      ];
    };
  };
}
