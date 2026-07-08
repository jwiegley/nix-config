# overlays/30-lazycodex.nix
# Purpose: LazyCodex installer and Codex agent harness tooling
# Packages: lazycodex-ai
_final: prev: {

  lazycodex-ai =
    with prev;
    stdenvNoCC.mkDerivation rec {
      pname = "lazycodex-ai";
      version = "4.16.0";
      npmPackage = "lazycodex-ai";

      src = fetchurl {
        url = "https://registry.npmjs.org/${npmPackage}/-/${npmPackage}-${version}.tgz";
        hash = "sha512-EUUbCdKKQ01xS2S6/x3qlTXNrw7fnjfi1dl2vFvNpcIQlFxEYGY9HyHTWxv+Kde3hT13SPP8wLBq+X9oCEIQGw==";
      };

      sourceRoot = "package";

      nativeBuildInputs = [
        makeWrapper
        uv
      ];

      dontPatchShebangs = true;
      dontFixup = true;

      installPhase = ''
        runHook preInstall

        mkdir -p "$out/lib/lazycodex-ai" "$out/bin"
        cp -R . "$out/lib/lazycodex-ai"
        chmod -R u+w "$out/lib/lazycodex-ai"

        makeWrapper ${nodejs_22}/bin/node "$out/bin/lazycodex-ai" \
          --add-flags "$out/lib/lazycodex-ai/packages/omo-codex/scripts/install-local.mjs" \
          --prefix PATH : ${
            lib.makeBinPath [
              bash
              git
              nodejs_22
              uv
            ]
          }
        ln -s lazycodex-ai "$out/bin/lazycodex"

        runHook postInstall
      '';

      doInstallCheck = true;
      installCheckPhase = ''
        runHook preInstallCheck

        "$out/bin/lazycodex-ai" version | grep -F "lazycodex-ai ${version}"
        "$out/bin/lazycodex" --help >/dev/null

        runHook postInstallCheck
      '';

      meta = with lib; {
        description = "Codex Light installer for the LazyCodex agent harness";
        homepage = "https://lazycodex.ai";
        license = licenses.unfreeRedistributable;
        mainProgram = "lazycodex-ai";
        platforms = platforms.unix;
      };
    };
}
