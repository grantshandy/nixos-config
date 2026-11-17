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
        inputs.colmena.packages.${system}.colmena
        pkgs.alejandra
        pkgs.git
      ];
    };
  };
}
