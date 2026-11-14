{inputs, ...}: {
  perSystem = {
    pkgs,
    stdenv,
    ...
  }: {
    formatter = pkgs.alejandra;

    devShells.default = pkgs.mkShell {
      packages = [
        inputs.agenix.packages.${stdenv.hostPlatform.system}.default
        pkgs.alejandra
        pkgs.git
      ];
    };
  };
}
