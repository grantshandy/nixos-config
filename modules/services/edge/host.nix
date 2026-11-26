# Resolves which machine terminates TLS for the fleet, so the edge proxy, the
# authorizer and the directory page all agree without any of them naming a host.
{
  config,
  lib,
  ...
}: {
  options.fleet.edgeHost = lib.mkOption {
    type = lib.types.str;
    readOnly = true;
    description = "Host name of the machine tagged \"edge\".";
  };

  config.fleet.edgeHost =
    config.fleet.hosts
    |> lib.filterAttrs (_: host: lib.elem "edge" host.tags)
    |> lib.attrNames
    |> (
      names:
        if lib.length names == 1
        then lib.head names
        else throw "exactly one host must carry the \"edge\" tag, found: ${lib.concatStringsSep ", " names}"
    );
}
