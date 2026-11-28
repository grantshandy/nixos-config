{
  lib,
  stdenvNoCC,
  fetchurl,
  fetchPnpmDeps,
  nodejs,
  pnpm,
  pnpmConfigHook,
  gnutar,
  gzip,
}:
stdenvNoCC.mkDerivation (finalAttrs: {
  pname = "perses-map-panel";
  version = "0.1.0";

  src = lib.cleanSourceWith {
    src = ./.;
    filter = path: type: let
      name = baseNameOf path;
    in
      !(lib.elem name ["node_modules" "dist"])
      && !(lib.hasSuffix ".tar.gz" name);
  };

  naturalEarth = fetchurl {
    url = "https://raw.githubusercontent.com/nvkelso/natural-earth-vector/v5.1.2/geojson/ne_110m_admin_0_countries.geojson";
    hash = "sha256-aGbId9Ocupw1diCHiDmzNtVp+MZi08+rTLHb4tOcl38=";
  };

  pnpmDeps = fetchPnpmDeps {
    inherit (finalAttrs) pname version src;
    inherit pnpm;
    hash = "sha256-0jMhii/GQbfJs6powiMOMQwlSeT4+ZThc6G21llbtvw=";
    fetcherVersion = 3;
  };

  nativeBuildInputs = [nodejs pnpm pnpmConfigHook gnutar gzip];

  buildPhase = ''
    runHook preBuild
    node scripts/generate-map.mjs "$naturalEarth" src/generated/world-map.ts
    pnpm type-check
    pnpm build
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    staging="$TMPDIR/PersesMapPanel"
    mkdir -p "$staging" "$out"
    cp -r dist/. "$staging/"
    cp -r schemas cue.mod "$staging/"
    cp package.json README.md LICENSE "$staging/"
    tar --sort=name --mtime='@1' --owner=0 --group=0 --numeric-owner \
      -C "$staging" -czf "$out/PersesMapPanel-${finalAttrs.version}.tar.gz" .
    runHook postInstall
  '';

  meta = {
    description = "SVG world map panel for Perses";
    license = lib.licenses.asl20;
    platforms = lib.platforms.all;
  };
})
