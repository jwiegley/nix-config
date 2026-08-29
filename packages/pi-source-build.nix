{
  buildNpmPackage,
  fd,
  fetchzip,
  git,
  lib,
  nodejs_24,
  piSource,
  ripgrep,
  stdenv,
}:

let
  sources = import ./source-catalog.nix "ai";
  source = sources.pi-coding-agent-source-build;
  packageMetadata = builtins.fromJSON (
    builtins.readFile (piSource.outPath + "/packages/coding-agent/package.json")
  );
  buildNpmPackageWithNode24 = buildNpmPackage.override { nodejs = nodejs_24; };
  piAiRelease =
    assert source.artifacts.piAiRelease.fetcher == "fetchzip";
    fetchzip source.artifacts.piAiRelease.args;
in
buildNpmPackageWithNode24 {
  pname = "pi-coding-agent-source-build";
  inherit (packageMetadata) version;

  src =
    assert source.version == packageMetadata.version;
    assert source.source.fetcher == "fetchTree";
    assert source.source.args.rev == piSource.rev;
    assert source.source.args.narHash == piSource.narHash;
    piSource.outPath;

  postPatch = ''
    mkdir -p packages/ai/src/providers/data
    cp -R ${piAiRelease}/dist/providers/data/. packages/ai/src/providers/data/
  '';

  npmDepsHash = source.hashes.npmDepsHash;
  npmInstallFlags = [ "--ignore-scripts" ];
  npmRebuildFlags = [ "--ignore-scripts" ];
  npmBuildScript = "build:offline";

  doCheck = true;
  nativeCheckInputs = [
    fd
    git
    ripgrep
  ];
  checkPhase = ''
    runHook preCheck
    # Backport vitest-dev/vitest#10893 for the bundled @vitest/utils 4.1.9.
    substituteInPlace node_modules/@vitest/utils/dist/source-map/node.js \
      --replace-fail \
        $'\tconst map = (convertSourceMap.fromSource(code) || convertSourceMap.fromMapFileSource(code, createConvertSourceMapReadMap(filePath)))?.toObject();' \
        $'\tlet map;\n\ttry {\n\t\tmap = (convertSourceMap.fromSource(code) || convertSourceMap.fromMapFileSource(code, createConvertSourceMapReadMap(filePath)))?.toObject();\n\t} catch {\n\t\treturn;\n\t}'
    node --input-type=module <<'JS'
    import assert from "node:assert/strict";
    import { extractSourcemapFromFile } from "./node_modules/@vitest/utils/dist/source-map/node.js";

    const map = { version: 3, sources: ["answer.ts"], mappings: "" };
    const valid = "const answer = 42\n//# sourceMappingURL=data:application/json;base64,"
      + Buffer.from(JSON.stringify(map)).toString("base64");
    assert.deepEqual(extractSourcemapFromFile(valid, "/answer.js"), { map });

    const malformed = "const sourceMapPrefix = `\n//# sourceMappingURL=data:application/json;base64,`, encode = map => btoa(JSON.stringify(map))";
    assert.equal(extractSourcemapFromFile(malformed, "/answer.js"), undefined);
    JS
    ${lib.optionalString stdenv.hostPlatform.isDarwin "npm run check"}
    ${lib.optionalString (!stdenv.hostPlatform.isDarwin) ''
      npm run check:pinned-deps
      npm run check:ts-imports
      npm run check:shrinkwrap
      npm run check:install-lock:coding-agent
      npm exec -- tsgo --noEmit
      npm run check:browser-smoke
    ''}
    # Run the fork's complete credential-free, non-e2e test gate.
    bash ./test.sh
    runHook postCheck
  '';

  installPhase = ''
    runHook preInstall
    mkdir -p "$out/coding-agent" "$out/agent" "$out/ai" "$out/workspace/packages"
    cp -R packages/coding-agent/dist "$out/coding-agent/dist"
    cp -R packages/agent/dist "$out/agent/dist"
    cp -R packages/ai/dist "$out/ai/dist"
    for name in protocol client server coding-agent agent ai tui telemetry; do
      mkdir -p "$out/workspace/packages/$name"
      cp "packages/$name/package.json" "$out/workspace/packages/$name/"
      cp -R "packages/$name/dist" "$out/workspace/packages/$name/dist"
    done
    scope="$out/workspace/node_modules/@earendil-works"
    mkdir -p "$scope"
    ln -s ../../packages/protocol "$scope/pi-protocol"
    ln -s ../../packages/client "$scope/pi-client"
    ln -s ../../packages/server "$scope/pi-server"
    ln -s ../../packages/coding-agent "$scope/pi-coding-agent"
    ln -s ../../packages/agent "$scope/pi-agent-core"
    ln -s ../../packages/ai "$scope/pi-ai"
    ln -s ../../packages/tui "$scope/pi-tui"
    ln -s ../../packages/telemetry "$scope/pi-telemetry"
    runHook postInstall
  '';
}
