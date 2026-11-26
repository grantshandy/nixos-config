{inputs, ...}: {
  perSystem = {
    lib,
    pkgs,
    system,
    ...
  }: let
    colmena = inputs.colmena.packages.${system}.colmena;

    fleetTreeRenderer = pkgs.writeText "fleet-tree.py" ''
      import json
      import sys

      fleet = json.load(sys.stdin)

      def modules(aspect):
          names = aspect["modules"]
          return ", ".join(names) if names else "no matching modules"

      def with_reason(aspects, reason):
          return [aspect for aspect in aspects if reason in aspect["reasons"]]

      for host_name, host in fleet.items():
          aspects = host["aspects"]
          host_aspect = next(aspect for aspect in aspects if "host" in aspect["reasons"])

          nodes = [("leaf", "host", host_aspect)]

          groups = [("default", with_reason(aspects, "default"))]
          groups.extend(
              (f"{tag} [tag]", with_reason(aspects, f"tag: {tag}"))
              for tag in host["tags"]
          )
          groups.extend([
              ("explicit", with_reason(aspects, "explicit")),
              ("host enrollment", with_reason(aspects, "host enrollment")),
              (
                  "services",
                  [
                      aspect
                      for aspect in aspects
                      if any(reason.startswith("service: ") for reason in aspect["reasons"])
                  ],
              ),
          ])
          nodes.extend(("group", label, members) for label, members in groups if members)

          print(f"{host_name} ({host['system']})")
          for index, (kind, label, value) in enumerate(nodes):
              last = index == len(nodes) - 1
              connector = "└─" if last else "├─"

              if kind == "leaf":
                  print(f"{connector} {label} ({modules(value)})")
                  continue

              print(f"{connector} {label}")
              child_prefix = "   " if last else "│  "
              for child_index, aspect in enumerate(value):
                  child_connector = "└─" if child_index == len(value) - 1 else "├─"
                  print(
                      f"{child_prefix}{child_connector} "
                      f"{aspect['name']} ({modules(aspect)})"
                  )
          print()
    '';

    fleetTree = pkgs.writeShellApplication {
      name = "fleet-tree";
      runtimeInputs = [pkgs.nix pkgs.python3];
      text = ''
        nix eval --json path:.#fleetDebug | python3 ${fleetTreeRenderer}
      '';
    };

    deployConfig = pkgs.writeShellApplication {
      name = "deploy-config";
      runtimeInputs = [pkgs.git pkgs.nix pkgs.openssh pkgs.jq];
      text = ''
        target_host="radon"
        remote="ssh-ng://$target_host"

        mapfile -t untracked < <(git ls-files --others --exclude-standard)
        if ((''${#untracked[@]} != 0)); then
          echo "deploy-config: refusing to deploy an incomplete Git flake." >&2
          echo "The following untracked files would be omitted:" >&2
          printf '  %s\n' "''${untracked[@]}" >&2
          echo "Stage them with 'git add' or remove them, then retry." >&2
          exit 1
        fi

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
        fleetTree
      ];
    };
  };
}
