{
  buildNpmPackage,
  fetchFromGitHub,
  fetchzip,
  nodejs_24,
}:

let
  sources = import ../../packages/source-catalog.nix "ai";
  source = sources.pi-classic-core-baseline;
  buildNpmPackageWithNode24 = buildNpmPackage.override { nodejs = nodejs_24; };
  upstream =
    assert source.source.fetcher == "fetchFromGitHub";
    fetchFromGitHub source.source.args;
  piAiRelease =
    assert source.artifacts.piAiRelease.fetcher == "fetchzip";
    fetchzip source.artifacts.piAiRelease.args;
in
buildNpmPackageWithNode24 {
  pname = "pi-classic-core-source";
  inherit (source) version;
  src = upstream;

  postPatch = ''
    mkdir -p packages/ai/src/providers/data
    cp -R ${piAiRelease}/dist/providers/data/. packages/ai/src/providers/data/
  '';

  npmDepsHash = source.hashes.npmDepsHash;
  npmInstallFlags = [ "--ignore-scripts" ];
  npmRebuildFlags = [ "--ignore-scripts" ];
  npmBuildScript = "build:offline";
  preBuild = ''
    test "$(node -p 'require("./packages/coding-agent/package.json").version')" = ${source.version}
    test "$(node -p 'require("./packages/ai/package.json").version')" = ${source.version}
  '';

  installPhase = ''
    runHook preInstall

    mkdir -p "$out/lib/node_modules"
    cp -RL node_modules/. "$out/lib/node_modules/"
    rm -rf "$out/lib/node_modules/@earendil-works"
    mkdir -p "$out/lib/node_modules/@earendil-works"

    installPackage() {
      local source_path=$1
      local package_name=$2
      local target="$out/lib/node_modules/@earendil-works/$package_name"
      mkdir -p "$target"
      cp "$source_path/package.json" "$target/"
      cp -R "$source_path/dist" "$target/"
    }

    installPackage packages/agent pi-agent-core
    installPackage packages/ai pi-ai
    installPackage packages/client pi-client
    installPackage packages/protocol pi-protocol
    installPackage packages/telemetry pi-telemetry
    installPackage packages/tui pi-tui
    installPackage packages/coding-agent pi-coding-agent

    session_manager="$out/lib/node_modules/@earendil-works/pi-coding-agent/dist/core/session-manager.js"
    test -s "$session_manager"
    test -s "$session_manager.map"
    NODE_PATH="$out/lib/node_modules" ${nodejs_24}/bin/node --input-type=module - "$session_manager" <<'JS'
    const { pathToFileURL } = await import("node:url");
    const module = await import(pathToFileURL(process.argv[2]));
    if (typeof module.SessionManager?.open !== "function") {
      throw new Error("built package does not export SessionManager.open");
    }
    JS

    cat > "$out/empty-extensions.json" <<'JSON'
    {"extensions":[]}
    JSON

    ${nodejs_24}/bin/node --input-type=module - \
      packages/coding-agent/src/core/session-manager.ts \
      packages/coding-agent/package.json \
      package-lock.json \
      "$session_manager" \
      "$out/empty-extensions.json" \
      "$out/b1-source-crosswalk.json" <<'JS'
    import { createHash } from "node:crypto";
    import { readFileSync, writeFileSync } from "node:fs";

    const [sourcePath, packagePath, lockPath, runtimePath, extensionPath, outputPath] = process.argv.slice(2);
    const source = readFileSync(sourcePath);
    const runtime = readFileSync(runtimePath);
    const sourceMap = readFileSync(`''${runtimePath}.map`);
    const parsedMap = JSON.parse(sourceMap);
    const sourceIndex = parsedMap.sources.findIndex((path) => path.endsWith("/src/core/session-manager.ts"));
    if (sourceIndex < 0 || parsedMap.sourcesContent[sourceIndex] !== source.toString()) {
      throw new Error("compiled SessionManager source map does not match the frozen source");
    }

    const lines = source.toString().split("\n");
    const locate = (text) => {
      const index = lines.findIndex((line) => line.includes(text));
      if (index < 0) throw new Error(`missing classic retention source evidence: ''${text}`);
      return index + 1;
    };
    const sha256 = (value) => createHash("sha256").update(value).digest("hex");
    const evidence = {
      schema: 1,
      hashes: {
        sessionManagerSource: sha256(source),
        codingAgentPackage: sha256(readFileSync(packagePath)),
        packageLock: sha256(readFileSync(lockPath)),
        sessionManagerRuntime: sha256(runtime),
        sessionManagerSourceMap: sha256(sourceMap),
        emptyExtensionManifest: sha256(readFileSync(extensionPath)),
      },
      sourceMap: parsedMap.sources[sourceIndex],
      runtime: {
        executable: process.execPath,
        version: process.version,
        executableSha256: sha256(readFileSync(process.execPath)),
      },
      causalLocations: {
        fileEntriesOwner: locate("private fileEntries: FileEntry[] = []"),
        byIdOwner: locate("private byId: Map<string, SessionEntry> = new Map()"),
        completeFileLoad: locate("this.fileEntries = preloadedFileEntries ?? loadEntriesFromFile"),
        indexAfterCompleteLoad: locate("this._buildIndex();"),
        indexOverCompleteEntries: locate("for (const entry of this.fileEntries)"),
        byIdPopulation: locate("this.byId.set(entry.id, entry)"),
        appendRetention: locate("this.fileEntries.push(entry)"),
        completeEntriesProjection: locate(
          'return this.fileEntries.filter((e): e is SessionEntry => e.type !== "session")',
        ),
        contextFromGetEntries: locate("return buildSessionContext(this.getEntries(), this.leafId, this.byId)"),
      },
    };
    writeFileSync(outputPath, `''${JSON.stringify(evidence, null, 2)}\n`);
    JS

    cat > "$out/b1-source-identity.json" <<'JSON'
    ${builtins.toJSON {
      schema = 1;
      repository = source.source.url;
      revision = source.source.args.rev;
      sourceHash = source.source.args.hash;
      inherit (source) version;
      npmDepsHash = source.hashes.npmDepsHash;
      providerDataArtifact = {
        url = source.artifacts.piAiRelease.url;
        hash = source.artifacts.piAiRelease.args.hash;
      };
      extensionManifest = [ ];
      downstreamPatches = [ ];
    }}
    JSON

    runHook postInstall
  '';
}
