# Flake-parts plumbing shared by the whole tree. The "modules" extra declares
# flake.modules.<class>.<aspect> as mergeable deferred modules, which is what
# lets several files contribute to one aspect.
{
  config,
  inputs,
  ...
}: {
  imports = [inputs.flake-parts.flakeModules.modules];

  systems = ["x86_64-linux" "aarch64-linux"];

  # Lets the registry be inspected without building a system, e.g.
  #   nix eval .#fleet.services --apply builtins.attrNames
  flake.fleet = config.fleet;
}
