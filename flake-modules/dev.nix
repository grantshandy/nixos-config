{inputs, ...}: {
  perSystem = {
    pkgs,
    system,
    ...
  }: let
    colmena = inputs.colmena.packages.${system}.colmena;

    buildRemote = pkgs.writeShellApplication {
      name = "build-remote";
      runtimeInputs = [pkgs.nix pkgs.openssh pkgs.jq];
      text = ''
        target_host="radon"
        remote="ssh-ng://$target_host"

        echo "🚀 Copying flake + inputs to $target_host..."
        meta=$(nix flake archive --json --dry-run .)
        src=$(jq -r .path <<<"$meta")
        mapfile -t paths < <(jq -r '.. | .path? // empty' <<<"$meta")
        nix copy --to "$remote" --substitute-on-destination "''${paths[@]}"

        echo "📦 Copying colmena to $target_host..."
        nix copy --to "$remote" --substitute-on-destination ${colmena}

        echo "🔨 Running colmena on $target_host..."
        ssh -t "$target_host" "
          set -e
          work=\$(mktemp -d /tmp/nixos-config.XXXXXX)
          trap 'rm -rf \"\$work\"' EXIT
          cp -rL --no-preserve=mode,ownership '$src'/. \"\$work\"
          cd \"\$work\"
          ${colmena}/bin/colmena apply --verbose --show-trace --parallel 1 $*
        "
      '';
    };
  in {
    formatter = pkgs.alejandra;
    devShells.default = pkgs.mkShell {
      packages = [
        inputs.agenix.packages.${system}.default
        colmena
        pkgs.alejandra
        pkgs.git
        buildRemote
      ];
    };
  };
}
