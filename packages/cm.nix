{
  autoPatchelfHook,
  cass,
  cmBun,
  darwin,
  fetchFromGitHub,
  fetchurl,
  git,
  lib,
  makeWrapper,
  openssh,
  openssl,
  python3,
  stdenv,
  stdenvNoCC,
  unzip,
  writableTmpDirAsHomeHook,
}:

let
  catalog = import ./source-catalog.nix "ai";
  source = catalog.cm;
  bunBaselineSource = catalog.bun-linux-x64-baseline;
  src = fetchFromGitHub source.source.args;
  licenseSha256 = "32a82e0a5754e72e51fae44b65a936c831c07376f21c90f5fb9e76897fcc3509";
  x86Linux = stdenvNoCC.hostPlatform.isx86_64 && stdenvNoCC.hostPlatform.isLinux;
  compileTarget = if x86Linux then "bun-linux-x64-baseline" else "bun";
  baselineRuntime = if x86Linux then fetchurl bunBaselineSource.source.args else null;

  node_modules = stdenvNoCC.mkDerivation {
    pname = "cm-node-modules";
    inherit (source) version;
    inherit src;

    __structuredAttrs = true;
    strictDeps = true;
    impureEnvVars = lib.fetchers.proxyImpureEnvVars ++ [
      "GIT_PROXY_COMMAND"
      "SOCKS_SERVER"
    ];
    nativeBuildInputs = [
      cmBun
      writableTmpDirAsHomeHook
    ];

    dontConfigure = true;
    buildPhase = ''
      runHook preBuild

      export BUN_INSTALL_CACHE_DIR="$(mktemp -d)"
      bun install \
        --cpu="*" \
        --os="*" \
        --frozen-lockfile \
        --ignore-scripts \
        --no-progress

      runHook postBuild
    '';
    installPhase = ''
      runHook preInstall

      mkdir -p "$out"
      cp -R -- node_modules "$out/"

      runHook postInstall
    '';

    dontFixup = true;
    outputHash = source.hashes.bunDepsHash;
    outputHashAlgo = "sha256";
    outputHashMode = "recursive";
  };
in
assert lib.assertMsg (
  stdenvNoCC.buildPlatform == stdenvNoCC.hostPlatform
) "cm does not support cross compilation";
assert cmBun.version == bunBaselineSource.version;
stdenvNoCC.mkDerivation {
  pname = "cm";
  inherit (source) version;
  inherit src;

  __structuredAttrs = true;
  strictDeps = true;
  patches = [ ../overlays/ai/patches/cm-environment-only-credentials.patch ];

  nativeBuildInputs = [
    cmBun
    git
    makeWrapper
    writableTmpDirAsHomeHook
  ]
  ++ lib.optional x86Linux autoPatchelfHook
  ++ lib.optional x86Linux unzip
  ++ lib.optional stdenvNoCC.hostPlatform.isDarwin darwin.autoSignDarwinBinariesHook;
  buildInputs = lib.optionals x86Linux [
    openssl
    stdenv.cc.cc.lib
  ];

  configurePhase = ''
    runHook preConfigure

    cp -R -- ${node_modules}/node_modules .
    chmod -R u+w node_modules

    set +e
    patch_output="$(bun scripts/patch-standalone-deps.mjs 2>&1)"
    patch_status=$?
    set -e
    printf '%s\n' "$patch_output"
    if [ "$patch_status" -ne 0 ]; then
      echo "cm dependency patcher failed with status $patch_status" >&2
      exit "$patch_status"
    fi
    test "$(printf '%s\n' "$patch_output" | grep -c '^\[patch-standalone-deps\] Patched ')" -eq 2
    printf '%s\n' "$patch_output" | grep -F       '[patch-standalone-deps] Done: 2 file(s) patched for standalone binary compatibility' >/dev/null
    if printf '%s\n' "$patch_output" | grep -F 'WARNING:' >/dev/null; then
      echo "cm dependency patcher reported a warning" >&2
      exit 1
    fi

    runHook postConfigure
  '';

  doCheck = true;
  checkPhase = ''
    runHook preCheck

    export HOME="$TMPDIR/home"
    unset XDG_CONFIG_HOME XDG_CACHE_HOME XDG_DATA_HOME CASS_MEMORY_HOME
    mkdir -p "$HOME"
    unset       OPENAI_API_KEY       ANTHROPIC_API_KEY       GOOGLE_GENERATIVE_AI_API_KEY       AWS_ACCESS_KEY_ID       AWS_SECRET_ACCESS_KEY       AWS_SESSION_TOKEN       AWS_SHARED_CREDENTIALS_FILE       AWS_CONFIG_FILE
    bun test \
      test/utils.inline-feedback.test.ts \
      test/security.test.ts \
      test/config.test.ts \
      test/privacy.test.ts
    bun node_modules/typescript/bin/tsc --noEmit

    runHook postCheck
  '';

  buildPhase = ''
    runHook preBuild

    ${lib.optionalString x86Linux ''
      compile_cache="$HOME/.bun/install/cache"
      mkdir -p "$compile_cache"
      unzip -p ${baselineRuntime} bun-linux-x64-baseline/bun \
        > "$compile_cache/bun-linux-x64-baseline-v${cmBun.version}"
      chmod 700 "$compile_cache/bun-linux-x64-baseline-v${cmBun.version}"
    ''}
    bun build src/cm.ts \
      --compile \
      --target=${compileTarget} \
      --no-compile-autoload-dotenv \
      --no-compile-autoload-bunfig \
      --compile-exec-argv=--use-system-ca \
      --outfile dist/cass-memory

    runHook postBuild
  '';

  # Bun appends the compiled bundle to its executable template. Never strip it.
  # The generic targets copy an already Nix-patched Bun; the x86 baseline
  # template instead needs autoPatchelf before it can execute on NixOS.
  dontStrip = true;
  dontPatchELF = !x86Linux;

  installPhase = ''
    runHook preInstall

    install -Dm755 dist/cass-memory "$out/libexec/cm/cm"
    install -Dm644 LICENSE "$out/share/licenses/cm/LICENSE"
    makeWrapper "$out/libexec/cm/cm" "$out/bin/cm"       --prefix PATH : ${
      lib.makeBinPath [
        cass
        git
        openssh
        python3
      ]
    }

    runHook postInstall
  '';

  doInstallCheck = true;
  installCheckPhase = ''
    runHook preInstallCheck

    test "$($out/bin/cm --version)" = "0.2.13"
    test "$(sha256sum "$out/share/licenses/cm/LICENSE" | cut -d ' ' -f1)" = "${licenseSha256}"
    cmp LICENSE "$out/share/licenses/cm/LICENSE"
    grep -F '${cass}/bin' "$out/bin/cm" >/dev/null
    grep -F '${git}/bin' "$out/bin/cm" >/dev/null
    grep -F '${openssh}/bin' "$out/bin/cm" >/dev/null
    grep -F '${python3}/bin' "$out/bin/cm" >/dev/null

    runHook postInstallCheck
  '';

  passthru = {
    inherit baselineRuntime compileTarget node_modules;
    buildBun = cmBun;
    upstreamVersion = "0.2.13";
  };

  meta = {
    description = "Procedural memory for AI coding agents";
    homepage = source.source.url;
    license = lib.licenses.unfree;
    mainProgram = "cm";
    sourceProvenance = [
      lib.sourceTypes.fromSource
      lib.sourceTypes.binaryNativeCode
    ];
    platforms = [
      "aarch64-darwin"
      "aarch64-linux"
      "x86_64-linux"
    ];
  };
}
