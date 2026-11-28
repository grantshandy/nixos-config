# ConvertX, a self-hosted file converter for documents, images, and media.
{...}: let
  port = 3030;
  stateDirectory = "convertx";
  dataDir = "/var/lib/${stateDirectory}";
in {
  fleet.services.ConvertX = {
    host = "radon";
    description = "File converter";
    subdomain = "convert";
    port = port;
    localProxy.port = port;
  };

  flake.modules.nixos.ConvertX = {
    lib,
    pkgs,
    ...
  }: let
    # Inlined from nixpkgs' by-name/co/convertx/package.nix so the runtime tool
    # list below can be trimmed -- the upstream derivation bakes in every
    # converter unconditionally (calibre, inkscape, texlive, markitdown's
    # PyQt6 stack, etc.).
    convertxVersion = "0.19.0";
    convertxSrc = pkgs.fetchFromGitHub {
      owner = "C4illin";
      repo = "ConvertX";
      tag = "v${convertxVersion}";
      hash = "sha256-7BaQSLl/LeXYOxpCIp0p+ucOsFkiI2JtGq9cm6iDNpM=";
    };

    convertxNodeModules = pkgs.stdenvNoCC.mkDerivation {
      pname = "convertx-node_modules";
      version = convertxVersion;
      src = convertxSrc;

      dontConfigure = true;
      dontFixup = true;

      nativeBuildInputs = [pkgs.bun];

      buildPhase = ''
        runHook preBuild
        bun install --frozen-lockfile --no-progress
        runHook postBuild
      '';

      installPhase = ''
        mkdir -p $out/lib/node_modules
        rm -rf ./node_modules/.cache
        rm -rf node_modules/.bin
        cp -R ./node_modules $out/lib
        cp package.json $out/lib
      '';

      outputHash = "sha256-lNjkyMF9SV65V8QKBleuYLcidbbEqqNb0CnuY/Jb1ow=";
      outputHashMode = "recursive";
    };

    convertxRuntimeTools = with pkgs; [
      ffmpeg-headless
      graphicsmagick
      imagemagick
      libheif
      libjxl
      libreoffice
      libva
      pandoc
      resvg
      vips
    ];

    convertx = pkgs.stdenvNoCC.mkDerivation {
      pname = "convertx";
      version = convertxVersion;
      src = convertxSrc;

      nativeBuildInputs = [
        pkgs.makeBinaryWrapper
        pkgs.tailwindcss_4
        pkgs.typescript
      ];

      dontConfigure = true;

      buildPhase = ''
        runHook preBuild

        ln -s ${convertxNodeModules}/lib/node_modules ./node_modules
        tailwindcss -i ./src/main.css -o ./public/generated.css
        tsc

        substituteInPlace ./dist/src/index.js \
          --replace-fail "assets: \"public\"" "assets: \"$out/share/convertx/dist/public\""

        runHook postBuild
      '';

      installPhase = ''
        mkdir -p $out/bin
        mkdir -p $out/share/convertx
        cp -R ./dist $out/share/convertx
        cp -R ./public $out/share/convertx/dist
        ln -s ${convertxNodeModules}/lib/node_modules $out

        makeBinaryWrapper ${pkgs.bun}/bin/bun $out/bin/convertx \
          --add-flags "run --prefer-offline --no-install $out/share/convertx/dist/src/index.js" \
          --set NODE_ENV production \
          --suffix PATH : ${lib.makeBinPath convertxRuntimeTools}
      '';

      meta = {
        description = "Self-hosted online file converter";
        mainProgram = "convertx";
      };
    };

    run = pkgs.writeShellApplication {
      name = "convertx-run";
      runtimeInputs = [pkgs.openssl convertx];
      text = ''
        secret_file="${dataDir}/jwt_secret"
        if [ ! -s "$secret_file" ]; then
          (umask 077 && openssl rand -hex 32 > "$secret_file")
        fi
        JWT_SECRET="$(cat "$secret_file")"
        export JWT_SECRET
        exec convertx
      '';
    };
  in {
    systemd.services.convertx = {
      description = "ConvertX file converter";
      wantedBy = ["multi-user.target"];
      after = ["network.target"];
      environment = {
        PORT = toString port;
        ACCOUNT_REGISTRATION = "false";
        HTTP_ALLOWED = "false";
        ALLOW_UNAUTHENTICATED = "true";
      };
      serviceConfig = {
        ExecStart = lib.getExe run;
        WorkingDirectory = dataDir;
        StateDirectory = stateDirectory;
        DynamicUser = true;
        Restart = "on-failure";
      };
    };
  };
}
