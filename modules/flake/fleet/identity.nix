# Personal and homelab facts, hoisted to the flake level so that modules which
# need to derive cross-host values (service URLs, tailnet names) can do so once
# instead of inside every system evaluation.
#
# Still typed per-system by legacy/options.nix; that duplication goes away when
# the last legacy consumer of `config.identity` is converted.
{lib, ...}: {
  options.fleet.identity = lib.mkOption {
    type = lib.types.raw;
    description = "Contents of ./identity.nix (gitignored in example deployments).";
  };

  config.fleet.identity = (import ../../../identity.nix).identity;
}
