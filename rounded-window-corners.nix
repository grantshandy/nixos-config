# a patched version of https://github.com/yilozt/rounded-window-corners for GNOME 45+

{ buildPackages, stdenv, fetchzip, ... }: stdenv.mkDerivation rec {
  pname = "gnome-shell-extension-rounded-window-corners";
  uuid = "rounded-window-corners@citri.one";

  name = pname;
  version = "12";

  src = fetchzip {
    url = "https://github.com/XenFour/rounded-window-corners/releases/download/master-release/${uuid}.zip";
    sha256 = "sha256-zabUtVKqtPkQgHzBVSEUNDgQbhv+yGF0iJPZKCLxTdY=";
    stripRoot = false;
  };

  nativeBuildInputs = [ buildPackages.glib ];
  buildPhase = ''
    runHook preBuild
    if [ -d schemas ]; then
      glib-compile-schemas --strict schemas
    fi
    runHook postBuild
  '';
  installPhase = ''
    runHook preInstall
    mkdir -p $out/share/gnome-shell/extensions/
    cp -r -T . $out/share/gnome-shell/extensions/${uuid}
    runHook postInstall
  '';
  passthru = {
    extensionPortalSlug = pname;
    extensionUuid = uuid;
  };
}
