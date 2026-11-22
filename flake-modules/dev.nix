{inputs, ...}: {
  perSystem = {
    lib,
    pkgs,
    system,
    ...
  }: let
    colmena = inputs.colmena.packages.${system}.colmena;

    deployConfig = pkgs.writeShellApplication {
      name = "deploy-config";
      runtimeInputs = [pkgs.nix pkgs.openssh pkgs.jq];
      text = ''
        target_host="radon"
        remote="ssh-ng://$target_host"

        echo "Copying flake + inputs to $target_host..."
        meta=$(nix flake archive --json --dry-run .)
        src=$(jq -r .path <<<"$meta")
        mapfile -t paths < <(jq -r '.. | .path? // empty' <<<"$meta")
        nix copy --to "$remote" --substitute-on-destination "''${paths[@]}"

        echo "Copying colmena to $target_host..."
        nix copy --to "$remote" --substitute-on-destination ${colmena}

        echo "Running colmena on $target_host..."
        ssh -t "$target_host" "
          set -e
          work=\"\$HOME/.local/state/nixos-config\"
          mkdir -p \"\$work\"
          # Replace the source but keep the GC roots from previous runs
          find \"\$work\" -mindepth 1 -maxdepth 1 ! -name .gcroots -exec rm -rf {} +
          cp -rL --no-preserve=mode,ownership '$src'/. \"\$work\"
          cd \"\$work\"
          ${lib.getExe colmena} apply --keep-result --verbose --show-trace $*
        "
      '';
    };
  in {
    formatter = pkgs.alejandra;
    devShells.default = pkgs.mkShell {
      packages = [
        inputs.agenix.packages.${system}.default
        pkgs.alejandra
        pkgs.git
        deployConfig
      ];
    };
  };
}
