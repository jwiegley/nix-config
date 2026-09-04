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
    # ponytail: remove when a pi-ai release includes Astra's generated catalog data.
    node --input-type=module <<'JS'
    import { createHash } from "node:crypto";
    import { readFileSync, readdirSync, writeFileSync } from "node:fs";
    import { join } from "node:path";

    const dataDir = "packages/ai/src/providers/data";
    const codexPath = join(dataDir, "openai-codex.json");
    const codex = JSON.parse(readFileSync(codexPath, "utf8"));
    codex["openai-codex-responses"]["gpt-6-astra"] = {
      id: "gpt-6-astra",
      name: "GPT-6 Astra",
      api: "openai-codex-responses",
      provider: "openai-codex",
      baseUrl: "https://chatgpt.com/backend-api",
      reasoning: true,
      input: ["text", "image"],
      cost: {
        input: 10,
        output: 50,
        cacheRead: 1,
        cacheWrite: 12.5,
        tiers: [{ inputTokensAbove: 272000, input: 20, output: 75, cacheRead: 2, cacheWrite: 25 }],
      },
      contextWindow: 272000,
      maxTokens: 128000,
      thinkingLevelMap: { off: null, minimal: "low", low: "low", medium: "medium", high: "high", xhigh: "xhigh", max: "max" },
      compat: { supportsOpenAIGrammarTools: true, supportsAdditionalTools: true, supportsToolSearch: true },
    };
    writeFileSync(codexPath, `''${JSON.stringify(codex)}\n`);

    const hash = value => createHash("sha256").update(value).digest("hex");
    const files = readdirSync(dataDir).filter(file => file.endsWith(".json")).sort();
    const structure = Object.fromEntries(files.map(file => {
      const groups = JSON.parse(readFileSync(join(dataDir, file), "utf8"));
      return [file.slice(0, -5), Object.fromEntries(Object.entries(groups).flatMap(([api, models]) =>
        Object.keys(models).map(modelId => [modelId, api])).sort(([a], [b]) => a.localeCompare(b)))];
    }).sort(([a], [b]) => a.localeCompare(b)));
    const manifestPath = join(dataDir, ".manifest.json");
    const manifest = JSON.parse(readFileSync(manifestPath, "utf8"));
    manifest.structureHash = hash(JSON.stringify(structure));
    manifest.files = Object.fromEntries(files.map(file => [file, hash(readFileSync(join(dataDir, file), "utf8"))]));
    writeFileSync(manifestPath, `''${JSON.stringify(manifest)}\n`);
    JS
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
