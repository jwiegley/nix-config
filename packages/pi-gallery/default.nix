{
  buildNpmPackage,
  buildPackages,
  chromium,
  esbuild,
  fetchFromGitHub,
  fetchurl,
  findutils,
  inputs,
  jq,
  lib,
  makeWrapper,
  patchelf,
  playwright-driver,
  python3,
  runCommand,
  stdenv,
  writeShellScript,
}:

let
  packageRoot = package: name: "${package}/share/pi-packages/${name}";

  manifest = import ./manifest.nix {
    inherit inputs;
    packages = {
      inherit
        agent-browser
        cymbal
        pi-agent-browser-native
        pi-artifacts
        pi-blackhole
        pi-btw
        pi-cache-optimizer
        pi-caveman
        pi-copy-message
        pi-cymbal
        pi-dynamic-workflows
        pi-goal-x
        pi-markdown-preview
        pi-rtk-optimizer
        pi-hashline-edit-pro
        pi-insights
        pi-knowledge-search
        pi-lens
        pi-loop
        pi-model-router
        pi-multi-pass
        pi-ponytail
        pi-provider-llama-swap
        pi-provider-omlx
        pi-rewind
        pi-smart-fetch
        pi-smart-web-search
        pi-session-search
        pi-subagents
        pi-trace-extension
        rtk
        ;
    };
  };
  inherit (manifest) members order supportSources;
  localModelMemberIds = [
    "llama-swap-provider"
    "omlx-provider"
    "router"
  ];
  activeOrder =
    if stdenv.hostPlatform.isDarwin then order else lib.subtractLists localModelMemberIds order;
  piCatalogRecords = manifest.sourceCatalog;
  sourceRecords = members // supportSources;
  catalogSourceIds = builtins.attrNames piCatalogRecords;
  gallerySourceIds = map (record: record.sourceName) (builtins.attrValues sourceRecords);
  externalSourceIds = builtins.attrNames manifest.externalSourceConsumers;
  sourceCatalogComplete =
    lib.sort builtins.lessThan (gallerySourceIds ++ externalSourceIds) == catalogSourceIds;
  normalizationContract = builtins.fromJSON (builtins.readFile ./normalization-policy.json);
  normalizationTargets = lib.sort builtins.lessThan (
    builtins.attrNames normalizationContract.targets
  );
  lockBearingTargets = lib.sort builtins.lessThan (
    lib.filter (
      id:
      let
        record = piCatalogRecords.${id};
      in
      (record.update.kind or null) == "npm-release"
      && (record.update.artifacts or [ ]) != [ ]
      && record.hashes ? npmDepsHash
    ) (builtins.attrNames piCatalogRecords)
  );
  galleryLockBearingTargets = lib.sort builtins.lessThan (
    map (id: sourceRecords.${id}.attrName) (
      lib.filter (id: (sourceRecords.${id}.update.normalizer or null) == "pi-gallery-v1") (
        builtins.attrNames sourceRecords
      )
    )
  );
  stringList =
    value:
    builtins.isList value
    && lib.all (item: builtins.isString item && item != "") value
    && builtins.length value == builtins.length (lib.unique value);
  stringMap =
    value:
    builtins.isAttrs value
    && lib.all (name: name != "" && builtins.isString value.${name} && value.${name} != "") (
      builtins.attrNames value
    );
  policyKeys = [
    "defensiveForbidDependencies"
    "forbidDependencies"
    "overrideDependencies"
    "removeTopLevel"
  ];
  policyValid =
    value:
    builtins.isAttrs value
    && lib.sort builtins.lessThan (builtins.attrNames value) == policyKeys
    && stringList value.defensiveForbidDependencies
    && stringList value.forbidDependencies
    && stringMap value.overrideDependencies
    && stringList value.removeTopLevel
    && lib.intersectLists value.defensiveForbidDependencies value.forbidDependencies == [ ];
  normalizationContractValid =
    lib.sort builtins.lessThan (builtins.attrNames normalizationContract) == [
      "common"
      "npmDependencyFlags"
      "schemaVersion"
      "targets"
    ]
    && normalizationContract.schemaVersion == 3
    &&
      normalizationContract.npmDependencyFlags == [
        "--ignore-scripts"
        "--omit=dev"
        "--omit=peer"
        "--legacy-peer-deps"
      ]
    && policyValid normalizationContract.common
    && lib.all policyValid (builtins.attrValues normalizationContract.targets)
    && lib.all (
      policy:
      let
        enforced = normalizationContract.common.forbidDependencies ++ policy.forbidDependencies;
        defensive =
          normalizationContract.common.defensiveForbidDependencies ++ policy.defensiveForbidDependencies;
        overrideNames =
          builtins.attrNames normalizationContract.common.overrideDependencies
          ++ builtins.attrNames policy.overrideDependencies;
      in
      stringList enforced
      && stringList defensive
      && builtins.length overrideNames == builtins.length (lib.unique overrideNames)
      && lib.intersectLists enforced defensive == [ ]
      && lib.intersectLists overrideNames (enforced ++ defensive) == [ ]
    ) (builtins.attrValues normalizationContract.targets)
    && lib.all (
      policy:
      lib.intersectLists (normalizationContract.common.removeTopLevel ++ policy.removeTopLevel) [
        "name"
        "version"
        "dependencies"
        "optionalDependencies"
      ] == [ ]
    ) (builtins.attrValues normalizationContract.targets);
  lockFileFor =
    member:
    let
      artifacts = member.update.artifacts or [ ];
      expected = "packages/pi-gallery/locks/${member.attrName}-package-lock.json";
    in
    assert artifacts == [ expected ];
    ../.. + "/${builtins.head artifacts}";
  releaseTarballs = lib.listToAttrs (
    lib.concatMap (
      id:
      let
        member = sourceRecords.${id};
      in
      lib.optional (member.source.fetcher == "fetchurl") (
        lib.nameValuePair member.attrName (fetchurl member.source.args)
      )
    ) (order ++ builtins.attrNames supportSources)
  );

  deniedNpx = writeShellScript "pi-lens-npx-disabled" ''
    echo "pi-lens: runtime package downloads are disabled; provide the tool through Nix or PATH" >&2
    exit 127
  '';

  mkReleaseSource =
    {
      name,
      tarball,
      lockFile,
      expectedName,
      expectedVersion,
      hashline ? false,
      lens ? false,
    }:
    runCommand "${name}-release-source"
      {
        nativeBuildInputs = [
          jq
          python3
        ];
      }
      ''
        mkdir -p "$out"
        tar -xzf ${tarball} -C "$out" --strip-components=1

        ${jq}/bin/jq \
          --arg target ${lib.escapeShellArg name} \
          --arg expectedName ${lib.escapeShellArg expectedName} \
          --arg expectedVersion ${lib.escapeShellArg expectedVersion} \
          --slurpfile policy ${./normalization-policy.json} \
          -f ${./normalize-manifest.jq} \
          "$out/package.json" > "$out/package.json.normalized"
        mv "$out/package.json.normalized" "$out/package.json"
        cp ${lockFile} "$out/package-lock.json"

        ${lib.optionalString hashline ''
          if grep -Fq 'async function tryLoadBetter(): Promise<boolean> {' \
            "$out/src/hash-store.ts"
          then
            substituteInPlace "$out/src/hash-store.ts" \
              --replace-fail \
                'async function tryLoadBetter(): Promise<boolean> {' \
                $'async function tryLoadBetter(): Promise<boolean> {\n  // Bun standalone aborts before the native import can fall back.\n  return false;'
          elif ! grep -Fq 'from "node:sqlite"' "$out/src/hash-store.ts"; then
            echo 'pi-hashline-edit-pro: unknown hash-store implementation' >&2
            exit 1
          fi
        ''}




        ${lib.optionalString lens ''
            ${python3}/bin/python3 - "$out" ${lib.escapeShellArg deniedNpx} <<'PY'
          from pathlib import Path
          import sys

          root = Path(sys.argv[1])
          denied_npx = sys.argv[2]

          installer = root / "dist/clients/installer/index.js"
          text = installer.read_text()
          start = text.index("export async function installTool(toolId) {")
          end = text.index("/**\n * Ensure a tool is installed", start)
          replacement = """export async function installTool(toolId) {
              logSessionStart(`auto-install ''${toolId}: disabled by Nix policy`);
              return false;
          }
          """
          installer.write_text(text[:start] + replacement + text[end:])

          interactive = root / "dist/clients/lsp/interactive-install.js"
          text = interactive.read_text()
          start = text.index("async function installTool(config) {")
          end = text.index("/**\n * Prompt user for installation", start)
          replacement = """async function installTool(_config) {
              return false;
          }
          """
          interactive.write_text(text[:start] + replacement + text[end:])

          policy = root / "dist/clients/tool-policy.js"
          text = policy.read_text()
          policy.write_text(text.replace("autoInstall: true", "autoInstall: false"))

          for path in (root / "dist").rglob("*.js"):
              text = path.read_text()
              new = text.replace('"npx.cmd"', repr(denied_npx)).replace('"npx"', repr(denied_npx))
              if new != text:
                  path.write_text(new)

          bundle = root / "dist/index.js"
          text = bundle.read_text()
          old = r'setStatus("pi-lens-lsp", parts.length > 0 ? parts.join(" \xB7 ") : theme.fg("dim", "LSP Inactive"));'
          new = 'setStatus("pi-lens-lsp", activeIds.length > 0 ? theme.bold("LSP") : theme.fg("dim", "LSP"));'
          if text.count(old) != 1:
              raise SystemExit("unexpected pi-lens status formatter")
          bundle.write_text(text.replace(old, new))

          for relative in ["dist/index.js", "dist/clients/runtime-tool-result.js"]:
              target = root / relative
              text = target.read_text()
              old = "const rawFilePath = event.input.path;"
              new = 'const rawPath = event.input.path;\n  const rawFilePath = typeof rawPath === "string" ? rawPath : void 0;'
              if text.count(old) != 1:
                  raise SystemExit(f"unexpected pi-lens tool-result path handling in {relative}")
              target.write_text(text.replace(old, new))
          PY
        ''}
      '';

  mkMemberReleaseSource =
    member: extra:
    mkReleaseSource (
      {
        name = member.attrName;
        tarball = releaseTarballs.${member.attrName};
        lockFile = lockFileFor member;
        expectedName = member.update.package;
        expectedVersion = member.version;
      }
      // extra
    );

  mkNpmPackageRoot =
    {
      pname,
      version,
      src,
      npmDepsHash,
      bundleEntry ? null,
      testBundleEntry ? null,
      prepareBundle ? (_root: ""),
      nodejs ? buildPackages.nodejs_22,
    }:
    buildNpmPackage {
      inherit
        pname
        version
        src
        npmDepsHash
        ;
      inherit nodejs;
      npmInstallFlags = normalizationContract.npmDependencyFlags;
      dontNpmBuild = true;
      makeCacheWritable = true;
      installPhase = ''
        runHook preInstall
        root="$out/share/pi-packages/${pname}"
        mkdir -p "$root"
        cp -R -- . "$root"/
        ${prepareBundle "$root"}
        ${lib.optionalString (bundleEntry != null) ''
          entry="$root/${bundleEntry}"
          output="$(dirname "$entry")/nix-bundle.js"
          ${esbuild}/bin/esbuild "$entry" \
            --bundle \
            --platform=node \
            --format=esm \
            --target=node22 \
            --external:'@earendil-works/*' \
            --external:typebox \
            --outfile="$output"
        ''}
        ${lib.optionalString (testBundleEntry != null) ''
          cat > "$NIX_BUILD_TOP/pi-package-pi-ai-shim.mjs" <<'EOF'
          export const getModel = () => undefined;
          export const getProviders = () => [];
          EOF
          cat > "$NIX_BUILD_TOP/pi-package-coding-agent-shim.mjs" <<'EOF'
          export const createAgentSession = () => { throw new Error("unreachable SDK shim"); };
          export class SessionManager {}
          EOF
          entry="$root/${testBundleEntry}"
          output="$(dirname "$entry")/nix-tmux-test-bundle.js"
          ${esbuild}/bin/esbuild "$entry" \
            --bundle \
            --platform=node \
            --format=esm \
            --target=node22 \
            --alias:@earendil-works/pi-ai/compat="$NIX_BUILD_TOP/pi-package-pi-ai-shim.mjs" \
            --alias:@earendil-works/pi-coding-agent="$NIX_BUILD_TOP/pi-package-coding-agent-shim.mjs" \
            --external:typebox \
            --outfile="$output"
        ''}
        runHook postInstall
      '';
    };

  hashlineSource = mkMemberReleaseSource members.hashline {
    hashline = true;
  };
  smartFetchSource = mkMemberReleaseSource members.smart-fetch { };
  smartWebSearchSource = mkMemberReleaseSource members.smart-web-search { };
  lensSource = mkMemberReleaseSource members.lens {
    lens = true;
  };
  markdownPreviewSource = mkMemberReleaseSource members.markdown-preview { };
  artifactsSource = mkMemberReleaseSource members.artifacts { };
  insightsSource = mkMemberReleaseSource members.insights { };
  knowledgeSearchSource = mkMemberReleaseSource members.knowledge-search { };
  sessionSearchSource = mkMemberReleaseSource members.session-search { };
  dynamicWorkflowsSource = mkMemberReleaseSource members.dynamic-workflows { };
  subagentsSource = mkMemberReleaseSource members.subagents { };

  pi-hashline-edit-pro = mkNpmPackageRoot {
    pname = members.hashline.attrName;
    version = members.hashline.version;
    src = hashlineSource;
    npmDepsHash = members.hashline.hashes.npmDepsHash;
  };
  pi-smart-fetch = mkNpmPackageRoot {
    pname = members.smart-fetch.attrName;
    version = members.smart-fetch.version;
    src = smartFetchSource;
    npmDepsHash = members.smart-fetch.hashes.npmDepsHash;
  };
  pi-smart-web-search = mkNpmPackageRoot {
    pname = members.smart-web-search.attrName;
    version = members.smart-web-search.version;
    src = smartWebSearchSource;
    npmDepsHash = members.smart-web-search.hashes.npmDepsHash;
  };
  pi-lens = mkNpmPackageRoot {
    pname = members.lens.attrName;
    version = members.lens.version;
    src = lensSource;
    npmDepsHash = members.lens.hashes.npmDepsHash;
  };
  pi-markdown-preview = mkNpmPackageRoot {
    pname = members.markdown-preview.attrName;
    version = members.markdown-preview.version;
    src = markdownPreviewSource;
    npmDepsHash = members.markdown-preview.hashes.npmDepsHash;
  };
  pi-dynamic-workflows = mkNpmPackageRoot {
    pname = members.dynamic-workflows.attrName;
    version = members.dynamic-workflows.version;
    src = dynamicWorkflowsSource;
    npmDepsHash = members.dynamic-workflows.hashes.npmDepsHash;
  };
  pi-subagents = mkNpmPackageRoot {
    pname = members.subagents.attrName;
    version = members.subagents.version;
    src = subagentsSource;
    npmDepsHash = members.subagents.hashes.npmDepsHash;
  };
  pi-artifacts = mkNpmPackageRoot {
    pname = members.artifacts.attrName;
    version = members.artifacts.version;
    src = artifactsSource;
    npmDepsHash = members.artifacts.hashes.npmDepsHash;
    bundleEntry = "extensions/index.ts";
    prepareBundle = root: ''
      ${python3}/bin/python3 - "${root}" <<'PY'
      from pathlib import Path
      import sys

      root = Path(sys.argv[1])
      markdown = root / "extensions/markdown.ts"
      text = markdown.read_text()
      text = text.replace(
          'import { createRequire } from "node:module";\n\nimport * as katex from "katex";',
          'import hljsImport from "highlight.js/lib/common";\n'
          'import MarkdownItImport from "markdown-it";\n'
          'import footnotePluginImport from "markdown-it-footnote";\n\n'
          'import * as katex from "katex";',
      )
      text = text.replace('\nconst require = createRequire(import.meta.url);\n', '\n')
      old_candidates = ["""const MarkdownIt = require("markdown-it") as MarkdownItConstructor;
      // `lib/common` bundles the ~40 common grammars instead of all ~190.
      const hljsModule = require("highlight.js/lib/common") as
        | HighlightJsLike
        | { default: HighlightJsLike };
      const hljs = "default" in hljsModule ? hljsModule.default : hljsModule;
      const footnotePlugin = require("markdown-it-footnote") as (
        md: MarkdownItInstance,
      ) => void;""", """const MarkdownIt = require("markdown-it") as MarkdownItConstructor;
      // `lib/common` bundles the ~40 common grammars instead of all ~190.
      const hljsModule = require("highlight.js/lib/common") as
        HighlightJsLike | { default: HighlightJsLike };
      const hljs = "default" in hljsModule ? hljsModule.default : hljsModule;
      const footnotePlugin = require("markdown-it-footnote") as (
        md: MarkdownItInstance,
      ) => void;"""]
      new = """const MarkdownIt = MarkdownItImport as unknown as MarkdownItConstructor;
      // `lib/common` bundles the ~40 common grammars instead of all ~190.
      const hljsModule = hljsImport as unknown as
        | HighlightJsLike
        | { default: HighlightJsLike };
      const hljs = "default" in hljsModule ? hljsModule.default : hljsModule;
      const footnotePlugin = footnotePluginImport as unknown as (
        md: MarkdownItInstance,
      ) => void;"""
      matches = [candidate for candidate in old_candidates if candidate in text]
      if len(matches) != 1:
          raise SystemExit("pi-artifacts markdown require block drifted")
      markdown.write_text(text.replace(matches[0], new))

      validation = root / "extensions/validation/html.ts"
      text = validation.read_text()
      text = text.replace(
          'import { createRequire } from "node:module";\n\nimport prettier from "prettier";',
          'import * as htmlhintModule from "htmlhint";\n\nimport prettier from "prettier";',
      )
      text = text.replace('\nconst require = createRequire(import.meta.url);\n', '\n')
      old = 'const { HTMLHint } = require("htmlhint") as { HTMLHint: HtmlHintLike };'
      new = (
          'const HTMLHint = (htmlhintModule as unknown as { HTMLHint: HtmlHintLike })'
          '.HTMLHint;'
      )
      if old not in text:
          raise SystemExit("pi-artifacts HTMLHint require block drifted")
      validation.write_text(text.replace(old, new))
      PY

      substituteInPlace "${root}/extensions/runtime.ts" \
        --replace-fail 'dirname(require.resolve("katex/dist/katex.min.css"))' \
          '"'"${root}/node_modules/katex/dist"'"' \
        --replace-fail 'dirname(require.resolve("chart.js"))' \
          '"'"${root}/node_modules/chart.js/dist"'"' \
        --replace-fail 'dirname(require.resolve("highlight.js/styles/github.min.css"))' \
          '"'"${root}/node_modules/highlight.js/styles"'"' \
        --replace-fail 'dirname(require.resolve("mermaid/dist/mermaid.min.js"))' \
          '"'"${root}/node_modules/mermaid/dist"'"' \
        --replace-fail 'dirname(require.resolve("@picocss/pico/css/pico.classless.min.css"))' \
          '"'"${root}/node_modules/@picocss/pico/css"'"'
    '';
  };
  pi-insights = mkNpmPackageRoot {
    pname = members.insights.attrName;
    version = members.insights.version;
    src = insightsSource;
    npmDepsHash = members.insights.hashes.npmDepsHash;
  };
  pi-session-search = mkNpmPackageRoot {
    pname = members.session-search.attrName;
    version = members.session-search.version;
    src = sessionSearchSource;
    npmDepsHash = members.session-search.hashes.npmDepsHash;
    nodejs = buildPackages.nodejs_24;
    prepareBundle = root: ''
      ${python3}/bin/python3 - "${root}/dist/index.js" 3 <<'PY'
      from pathlib import Path
      import re
      import sys

      source = Path(sys.argv[1])
      expected = int(sys.argv[2])
      text = source.read_text()
      pattern = re.compile(
          r'import \{ DatabaseSync(?: as ([A-Za-z0-9_$]+))? \} from "node:sqlite";'
      )

      def replace(match):
          alias = match.group(1) or "DatabaseSync"
          return f'import {{ Database as {alias} }} from "bun:sqlite";'

      text, count = pattern.subn(replace, text)
      if count != expected:
          raise SystemExit(f"unexpected node:sqlite import count: {count} != {expected}")

      hardening_replacements = {
          'import { readFileSync, writeFileSync, existsSync, mkdirSync } from "node:fs";':
              'import { readFileSync, writeFileSync, existsSync, mkdirSync, chmodSync } from "node:fs";',
          'import { mkdirSync as mkdirSync2, statSync as statSync2 } from "node:fs";':
              'import { mkdirSync as mkdirSync2, statSync as statSync2, chmodSync as chmodSync2 } from "node:fs";',
          'import { readFileSync as readFileSync3, writeFileSync as writeFileSync2, existsSync as existsSync3, mkdirSync as mkdirSync3, statSync as statSync3 } from "node:fs";':
              'import { readFileSync as readFileSync3, writeFileSync as writeFileSync2, existsSync as existsSync3, mkdirSync as mkdirSync3, statSync as statSync3, chmodSync as chmodSync3 } from "node:fs";',
          '  if (!existsSync(configFile)) return null;\n  const raw = readFileSync(configFile, "utf8");':
          '  if (!existsSync(configFile)) return null;\n'
              '  chmodSync(dirname(configFile), 0o700);\n'
              '  chmodSync(configFile, 0o600);\n'
              '  const raw = readFileSync(configFile, "utf8");',
          '  mkdirSync(dirname(configFile), { recursive: true });\n'
          '  writeFileSync(configFile, JSON.stringify(file, null, 2), "utf8");':
              '  mkdirSync(dirname(configFile), { recursive: true, mode: 0o700 });\n'
              '  chmodSync(dirname(configFile), 0o700);\n'
              '  writeFileSync(configFile, JSON.stringify(file, null, 2), { encoding: "utf8", mode: 0o600 });\n'
              '  chmodSync(configFile, 0o600);',
          '    mkdirSync2(indexDir, { recursive: true });\n'
          '    this.dbPath = join3(indexDir, "sessions-fts.db");':
              '    mkdirSync2(indexDir, { recursive: true, mode: 0o700 });\n'
              '    chmodSync2(indexDir, 0o700);\n'
              '    this.dbPath = join3(indexDir, "sessions-fts.db");',
          '    this.db = new DatabaseSync2(this.dbPath);\n'
          '    this.db.exec("PRAGMA busy_timeout = 5000;");':
              '    this.db = new DatabaseSync2(this.dbPath);\n'
              '    chmodSync2(this.dbPath, 0o600);\n'
              '    this.db.exec("PRAGMA busy_timeout = 5000;");',
          '    this.db = new DatabaseSync3(join4(indexDir, "hybrid-fts.db"));\n'
          '    this.db.exec("PRAGMA busy_timeout = 5000;");':
              '    const dbPath = join4(indexDir, "hybrid-fts.db");\n'
              '    this.db = new DatabaseSync3(dbPath);\n'
              '    chmodSync3(dbPath, 0o600);\n'
              '    this.db.exec("PRAGMA busy_timeout = 5000;");',
          '    mkdirSync3(indexDir, { recursive: true });\n'
          '    this.indexPath = join4(indexDir, "session-index.json");':
              '    mkdirSync3(indexDir, { recursive: true, mode: 0o700 });\n'
              '    chmodSync3(indexDir, 0o700);\n'
              '    this.indexPath = join4(indexDir, "session-index.json");',
          '    if (!existsSync3(this.indexPath)) return;\n'
          '    try {':
              '    if (!existsSync3(this.indexPath)) return;\n'
              '    chmodSync3(this.indexPath, 0o600);\n'
              '    try {',
          '    writeFileSync2(this.indexPath, JSON.stringify(this.data), "utf8");':
              '    writeFileSync2(this.indexPath, JSON.stringify(this.data), { encoding: "utf8", mode: 0o600 });\n'
              '    chmodSync3(this.indexPath, 0o600);',
      }
      for old, new in hardening_replacements.items():
          if text.count(old) != 1:
              raise SystemExit(f"unexpected session-search privacy seam: {old[:60]!r}")
          text = text.replace(old, new)

      lifecycle_replacements = {
          '  let shuttingDown = false;':
              '  let shuttingDown = false;\n'
              '  let sessionGeneration = 0;\n'
              '  async function resetSession() {\n'
              '    shuttingDown = true;\n'
              '    sessionGeneration++;\n'
              '    if (syncTimer) {\n'
              '      clearInterval(syncTimer);\n'
              '      syncTimer = null;\n'
              '    }\n'
              '    for (const handle of pendingTimers) clearTimeout(handle);\n'
              '    pendingTimers.clear();\n'
              '    const previousIndex = sessionIndex;\n'
              '    sessionIndex = null;\n'
              '    currentConfig = null;\n'
              '    if (previousIndex && "close" in previousIndex) {\n'
              '      await previousIndex.close();\n'
              '    }\n'
              '  }',
          '  pi.on("session_start", async (_event, ctx) => {\n'
          '    sessionCwd = ctx.cwd;':
              '  pi.on("session_start", async (_event, ctx) => {\n'
              '    await resetSession();\n'
              '    shuttingDown = false;\n'
              '    const generation = sessionGeneration;\n'
              '    sessionCwd = ctx.cwd;',
          '    void startIndex(currentConfig, ctx, syncAction, initialAction);':
              '    await startIndex(currentConfig, ctx, syncAction, initialAction, generation);',
          '  async function startIndex(config, ctx, syncAction, initialAction) {\n'
          '    try {':
              '  async function startIndex(config, ctx, syncAction, initialAction, generation) {\n'
              '    const isCurrent = () => generation === sessionGeneration && !shuttingDown;\n'
              '    try {',
          '      await sessionIndex.load();\n'
          '      if (config?.primer?.enabled === false) {':
              '      const activeIndex = sessionIndex;\n'
              '      await activeIndex.load();\n'
              '      if (!isCurrent()) {\n'
              '        await activeIndex.close();\n'
              '        return;\n'
              '      }\n'
              '      if (config?.primer?.enabled === false) {',
          '          sessionIndex.sync(\n':
              '          activeIndex.sync(\n',
          '`Sessions: ''${parts.join(" ")} (''${sessionIndex?.size() ?? 0} total)`':
              '`Sessions: ''${parts.join(" ")} (''${activeIndex.size()} total)`',
          '          setImmediate(() => {\n'
          '            runSync().then(handleSyncResult).catch((err) => {':
              '          scheduleTimer(() => {\n'
              '            runSync().then(handleSyncResult).catch((err) => {',
          '          });\n'
          '        }\n'
          '      }\n'
          '      const action = syncAction':
              '          }, 0);\n'
              '        }\n'
              '      }\n'
              '      const action = syncAction',
          '          if (!sessionIndex || shuttingDown) return;\n'
          '          try {\n'
          '            const result = await sessionIndex.sync();':
              '          if (!isCurrent()) return;\n'
              '          try {\n'
              '            const result = await activeIndex.sync();',
          '`Sessions synced: ''${parts.join(" ")} (''${sessionIndex.size()} total)`':
              '`Sessions synced: ''${parts.join(" ")} (''${activeIndex.size()} total)`',
          '    } catch (err) {\n'
          '      sessionIndex = null;':
              '    } catch (err) {\n'
              '      if (!isCurrent()) return;\n'
              '      sessionIndex = null;',
          '  pi.on("session_shutdown", async () => {\n'
          '    shuttingDown = true;\n'
          '    if (syncTimer) {\n'
          '      clearInterval(syncTimer);\n'
          '      syncTimer = null;\n'
          '    }\n'
          '    for (const handle of pendingTimers) {\n'
          '      clearTimeout(handle);\n'
          '    }\n'
          '    pendingTimers.clear();\n'
          '    if (sessionIndex && "close" in sessionIndex) {\n'
          '      sessionIndex.close();\n'
          '    }\n'
          '  });':
              '  pi.on("session_shutdown", resetSession);',
      }
      for old, new in lifecycle_replacements.items():
          if text.count(old) != 1:
              raise SystemExit(f"unexpected session-search lifecycle seam: {old[:60]!r}")
          text = text.replace(old, new)

      start = text.index('  async function startIndex(')
      end = text.index('  pi.on("session_shutdown"', start)
      lifecycle = text[start:end]
      lifecycle = lifecycle.replace('if (shuttingDown) return;', 'if (!isCurrent()) return;')
      text = text[:start] + lifecycle + text[end:]

      stale_runtime_message = (
          'SQLite FTS5 is not available in this Node runtime. '
          'pi-session-search requires Node 24+ (where node:sqlite ships with FTS5 compiled in). '
          'Current: Node ''${process.versions.node}. Upgrade Node and restart pi.'
      )
      bun_runtime_message = (
          'SQLite FTS5 is not available in this Bun runtime. '
          'Use the Nix-managed Pi package and restart Pi.'
      )
      if text.count(stale_runtime_message) != 1:
          raise SystemExit("unexpected session-search FTS5 runtime guidance")
      text = text.replace(stale_runtime_message, bun_runtime_message)
      source.write_text(text)

      readme = source.parent.parent / "README.md"
      readme_text = readme.read_text()
      if readme_text.count("LiteLLM") != 2:
          raise SystemExit("unexpected session-search proxy examples")
      readme.write_text(readme_text.replace("LiteLLM, ", ""))
      PY
    '';
  };
  pi-knowledge-search = mkNpmPackageRoot {
    pname = members.knowledge-search.attrName;
    version = members.knowledge-search.version;
    src = knowledgeSearchSource;
    npmDepsHash = members.knowledge-search.hashes.npmDepsHash;
    nodejs = buildPackages.nodejs_24;
    prepareBundle = root: ''
      ${python3}/bin/python3 - \
        "${root}/dist/index.js" "${root}/dist/sync-worker.mjs" \
        2 ${buildPackages.nodejs_24}/bin/node <<'PY'
      from pathlib import Path
      import re
      import sys

      source = Path(sys.argv[1])
      worker_source = Path(sys.argv[2])
      expected = int(sys.argv[3])
      node = sys.argv[4]
      text = source.read_text()
      pattern = re.compile(
          r'import \{ DatabaseSync(?: as ([A-Za-z0-9_$]+))? \} from "node:sqlite";'
      )

      def replace(match):
          alias = match.group(1) or "DatabaseSync"
          return f'import {{ Database as {alias} }} from "bun:sqlite";'

      text, count = pattern.subn(replace, text)
      if count != expected:
          raise SystemExit(f"unexpected node:sqlite import count: {count} != {expected}")

      implicit_openai = """const providerType = envStr("KNOWLEDGE_SEARCH_PROVIDER") ?? file?.provider?.type ?? // Convenience default: if OPENAI_API_KEY is exported and nothing else
        // is configured, assume the user wants the openai provider.
        (process.env.OPENAI_API_KEY ? "openai" : void 0);"""
      explicit_provider = """const providerType = envStr("KNOWLEDGE_SEARCH_PROVIDER") ?? file?.provider?.type;"""
      worker_text = worker_source.read_text()
      if text.count(implicit_openai) != 1 or worker_text.count(implicit_openai) != 1:
          raise SystemExit("unexpected knowledge-search implicit OpenAI fallback")
      text = text.replace(implicit_openai, explicit_provider)
      worker_text = worker_text.replace(implicit_openai, explicit_provider)

      readme = source.parent.parent / "README.md"
      readme_text = readme.read_text()
      legacy_proxy = "[litellm](https://docs.litellm.ai/), "
      if readme_text.count(legacy_proxy) != 1:
          raise SystemExit("unexpected knowledge-search proxy example")
      readme.write_text(readme_text.replace(legacy_proxy, ""))

      worker_start = "const worker = fork(workerPath, [], {\n        stdio:"
      worker_replacement = (
          "const worker = fork(workerPath, [], {\n"
          f'        execPath: "{node}",\n'
          "        stdio:"
      )
      if text.count(worker_start) != 1:
          raise SystemExit("unexpected knowledge-search worker launch")
      text = text.replace(worker_start, worker_replacement)

      lifecycle_replacements = {
          '  let workerExitExpected = false;':
              '  let workerExitExpected = false;\n'
              '  let activeWorker = null;\n'
              '  let restartTimer = null;\n'
              '  let statusTimer = null;\n'
              '  async function stopWorker() {\n'
              '    workerExitExpected = true;\n'
              '    if (restartTimer) {\n'
              '      clearTimeout(restartTimer);\n'
              '      restartTimer = null;\n'
              '    }\n'
              '    if (statusTimer) {\n'
              '      clearTimeout(statusTimer);\n'
              '      statusTimer = null;\n'
              '    }\n'
              '    const worker = activeWorker;\n'
              '    activeWorker = null;\n'
              '    if (!worker) return;\n'
              '    worker.removeAllListeners("exit");\n'
              '    worker.ref();\n'
              '    await new Promise((resolve) => {\n'
              '      let forceTimer = null;\n'
              '      let finished = false;\n'
              '      const finish = () => {\n'
              '        if (finished) return;\n'
              '        finished = true;\n'
              '        if (forceTimer) clearTimeout(forceTimer);\n'
              '        resolve();\n'
              '      };\n'
              '      worker.once("exit", finish);\n'
              '      if (worker.exitCode !== null || worker.signalCode !== null) {\n'
              '        finish();\n'
              '        return;\n'
              '      }\n'
              '      forceTimer = setTimeout(() => {\n'
              '        if (worker.exitCode === null && worker.signalCode === null) worker.kill("SIGKILL");\n'
              '      }, 2e3);\n'
              '      worker.stdout?.destroy();\n'
              '      worker.stderr?.destroy();\n'
              '      if (worker.connected) worker.disconnect();\n'
              '      worker.kill("SIGTERM");\n'
              '    });\n'
              '  }',
          '    sessionCwd = ctx.cwd;':
              '    await stopWorker();\n'
              '    const previousIndex = index;\n'
              '    index = null;\n'
              '    kbSearcher = null;\n'
              '    currentConfig = null;\n'
              '    syncDone = false;\n'
              '    await previousIndex?.close();\n'
              '    sessionCwd = ctx.cwd;\n'
              '    workerExitExpected = false;',
          '      let stdout = "";':
              '      activeWorker = worker;\n'
              '      const workerIndex = index;\n'
              '      let stdout = "";',
          '      worker.on("exit", async (code, signal) => {\n'
          '        syncDone = true;':
              '      worker.on("exit", async (code, signal) => {\n'
              '        if (activeWorker === worker) activeWorker = null;\n'
              '        if (workerExitExpected) return;',
          '            await index.load();\n'
          '            const changes = result.added + result.updated + result.removed;':
              '            await workerIndex.load();\n'
              '            if (index !== workerIndex || workerExitExpected) return;\n'
              '            const changes = result.added + result.updated + result.removed;',
          '              setTimeout(() => ctx.ui.setStatus("knowledge-search", ""), 5e3);':
              '              statusTimer = setTimeout(() => {\n'
              '                statusTimer = null;\n'
              '                if (!workerExitExpected) ctx.ui.setStatus("knowledge-search", "");\n'
              '              }, 5e3);',
          '            setTimeout(() => {\n'
          '              if (!workerExitExpected) spawnWorker();\n'
          '            }, 2e3);':
              '            restartTimer = setTimeout(() => {\n'
              '              restartTimer = null;\n'
              '              if (!workerExitExpected) spawnWorker();\n'
              '            }, 2e3);',
          '  pi.on("session_shutdown", async () => {\n'
          '    workerExitExpected = true;\n'
          '    await index?.close();\n'
          '  });':
              '  pi.on("session_shutdown", async () => {\n'
              '    await stopWorker();\n'
              '    const previousIndex = index;\n'
              '    index = null;\n'
              '    kbSearcher = null;\n'
              '    currentConfig = null;\n'
              '    await previousIndex?.close();\n'
              '  });',
      }
      for old, new in lifecycle_replacements.items():
          if text.count(old) != 1:
              raise SystemExit(f"unexpected knowledge-search lifecycle anchor: {old[:60]!r}")
          text = text.replace(old, new)

      worker_handler_start = text.index('      worker.on("exit", async (code, signal) => {')
      worker_handler_end = text.index(
          '        } else if (code !== 0 && !workerExitExpected) {',
          worker_handler_start,
      )
      worker_handler = text[worker_handler_start:worker_handler_end]
      worker_handler_replacements = {
          '        if (activeWorker === worker) activeWorker = null;\n'
          '        if (workerExitExpected) return;':
              '        const currentWorker = activeWorker === worker;\n'
              '        if (currentWorker) activeWorker = null;\n'
              '        if (!currentWorker || workerExitExpected) return;',
          '            const result = JSON.parse(stdout);':
              '            if (!stdout.trim()) throw new Error("worker produced no result");\n'
              '            const result = JSON.parse(stdout);\n'
              '            for (const key of ["added", "updated", "removed", "size", "chunks"]) {\n'
              '              if (!Number.isFinite(result[key])) throw new Error(`invalid worker field: ''${key}`);\n'
              '            }',
          '            if (index !== workerIndex || workerExitExpected) return;\n'
          '            const changes = result.added + result.updated + result.removed;':
              '            if (index !== workerIndex || workerExitExpected) return;\n'
              '            syncDone = true;\n'
              '            const changes = result.added + result.updated + result.removed;',
          '          } catch {\n'
          '          }':
              '          } catch (err) {\n'
              '            if (index !== workerIndex || workerExitExpected) return;\n'
              '            syncDone = false;\n'
              '            const message = err instanceof Error ? err.message : String(err);\n'
              '            console.error(`knowledge-search: worker result rejected: ''${message}`);\n'
              '          }',
      }
      for old, new in worker_handler_replacements.items():
          if worker_handler.count(old) != 1:
              raise SystemExit(f"unexpected knowledge-search worker result seam: {old[:50]!r}")
          worker_handler = worker_handler.replace(old, new)
      if worker_handler.count('        if (code === 0 && stdout) {') != 1:
          raise SystemExit("unexpected knowledge-search successful worker branch")
      worker_handler = worker_handler.replace(
          '        if (code === 0 && stdout) {',
          '        if (code === 0) {',
      )
      text = text[:worker_handler_start] + worker_handler + text[worker_handler_end:]

      privacy_replacements = {
          '  if (fs.existsSync(configPath)) {\n    try {':
              '  if (fs.existsSync(configPath)) {\n'
              '    try {\n'
              '      fs.chmodSync(path.dirname(configPath), 0o700);\n'
              '      fs.chmodSync(configPath, 0o600);',
          'import { mkdirSync as mkdirSync2 } from "node:fs";':
              'import { mkdirSync as mkdirSync2, chmodSync as chmodSync2 } from "node:fs";',
          '    mkdirSync2(indexDir, { recursive: true });\n'
          '    this.dbPath = join2(indexDir, "kb-fts.db");':
              '    mkdirSync2(indexDir, { recursive: true, mode: 0o700 });\n'
              '    chmodSync2(indexDir, 0o700);\n'
              '    this.dbPath = join2(indexDir, "kb-fts.db");',
          '    this.db = new DatabaseSync2(this.dbPath);\n'
          '    this.db.exec("PRAGMA busy_timeout = 5000;");':
              '    this.db = new DatabaseSync2(this.dbPath);\n'
              '    chmodSync2(this.dbPath, 0o600);\n'
              '    this.db.exec("PRAGMA busy_timeout = 5000;");',
          '    if (fs2.existsSync(indexFile)) {\n      try {':
              '    if (fs2.existsSync(indexFile)) {\n'
              '      try {\n'
              '        fs2.chmodSync(indexFile, 0o600);',
          '    fs2.mkdirSync(this.config.indexDir, { recursive: true });':
              '    fs2.mkdirSync(this.config.indexDir, { recursive: true, mode: 0o700 });\n'
              '    fs2.chmodSync(this.config.indexDir, 0o700);',
          '      await fs2.promises.writeFile(tmpFile, serialised);':
              '      await fs2.promises.writeFile(tmpFile, serialised, { mode: 0o600 });',
          '    const stream = fs2.createWriteStream(tmpFile);':
              '    const stream = fs2.createWriteStream(tmpFile, { mode: 0o600 });',
      }

      def harden_knowledge(bundle, label):
          for old, new in privacy_replacements.items():
              if bundle.count(old) != 1:
                  raise SystemExit(f"unexpected {label} privacy seam: {old[:60]!r}")
              bundle = bundle.replace(old, new)
          rename = '\n          await fs2.promises.rename(tmpFile, finalFile);'
          if bundle.count(rename) != 1:
              raise SystemExit(f"unexpected {label} streaming rename seam")
          bundle = bundle.replace(
              rename,
              rename + '\n          await fs2.promises.chmod(finalFile, 0o600);',
          )
          rename = '\n      await fs2.promises.rename(tmpFile, finalFile);'
          if bundle.count(rename) != 1:
              raise SystemExit(f"unexpected {label} regular rename seam")
          bundle = bundle.replace(
              rename,
              rename + '\n      await fs2.promises.chmod(finalFile, 0o600);',
          )
          return bundle

      text = harden_knowledge(text, "knowledge-search main bundle")
      worker_text = harden_knowledge(worker_text, "knowledge-search worker")

      config_write = (
          '  fs.mkdirSync(dir, { recursive: true });\n'
          '  fs.writeFileSync(configPath, JSON.stringify(config, null, 2) + "\\n");'
      )
      config_write_private = (
          '  fs.mkdirSync(dir, { recursive: true, mode: 0o700 });\n'
          '  fs.chmodSync(dir, 0o700);\n'
          '  fs.writeFileSync(configPath, JSON.stringify(config, null, 2) + "\\n", { mode: 0o600 });\n'
          '  fs.chmodSync(configPath, 0o600);'
      )
      if text.count(config_write) != 1:
          raise SystemExit("unexpected knowledge-search config write seam")
      text = text.replace(config_write, config_write_private)

      worker_completion = """index.sync().then(({ added, updated, removed }) => {
        const result = JSON.stringify({
          added,
          updated,
          removed,
          size: index.size(),
          chunks: index.chunkCount()
        });
        process.stdout.write(result);
        process.exit(0);
      }).catch((err) => {"""
      worker_completion_replacement = """index.sync().then(async ({ added, updated, removed }) => {
        await index.close();
        const result = JSON.stringify({
          added,
          updated,
          removed,
          size: index.size(),
          chunks: index.chunkCount()
        });
        process.stdout.write(result, () => process.exit(0));
      }).catch((err) => {"""
      if worker_text.count(worker_completion) != 1:
          raise SystemExit("unexpected knowledge-search worker completion")
      worker_text = worker_text.replace(worker_completion, worker_completion_replacement)

      source.write_text(text)
      worker_source.write_text(worker_text)
      PY
    '';
  };

  mkCopyRoot =
    {
      pname,
      version,
      install,
    }:
    runCommand "${pname}-${version}" { passthru = { inherit version; }; } ''
      root="$out/share/pi-packages/${pname}"
      mkdir -p "$root"
      ${install "$root"}
    '';

  pi-loop = mkCopyRoot {
    pname = supportSources.loop.attrName;
    version = supportSources.loop.version;
    install = root: ''
      cp -R -- ${fetchFromGitHub supportSources.loop.source.args}/. ${root}/
      substituteInPlace ${root}/extensions/index.ts \
        --replace-fail \
          'if (entries[index]?.role === "assistant") {' \
          'if ((entries[index]?.message ?? entries[index])?.role === "assistant") {' \
        --replace-fail \
          'return messageToText(entries[index]);' \
          'return messageToText(entries[index]?.message ?? entries[index]);'
    '';
  };

  mkLocalProvider =
    member: extensionSource:
    let
      upstream = fetchFromGitHub member.source.args;
      packageManifest = builtins.toJSON {
        name = member.publicName;
        inherit (member) version;
        type = "module";
        license = "Apache-2.0";
        pi.extensions = [ "./index.ts" ];
      };
    in
    mkCopyRoot {
      pname = member.attrName;
      inherit (member) version;
      install = root: ''
        cp -- ${extensionSource} ${root}/index.ts
        cp -- ${./providers/local-openai-provider.ts} ${root}/local-openai-provider.ts
        cp -- ${upstream}/LICENSE ${root}/LICENSE
        printf '%s\n' ${lib.escapeShellArg packageManifest} > ${root}/package.json
      '';
    };

  pi-provider-llama-swap = mkLocalProvider members.llama-swap-provider ./providers/pi-provider-llama-swap.ts;
  pi-provider-omlx = mkLocalProvider members.omlx-provider ./providers/pi-provider-omlx.ts;

  pi-btw = mkCopyRoot {
    pname = members.btw.attrName;
    version = members.btw.version;
    install = root: ''
      tar -xzf ${releaseTarballs.pi-btw} -C ${root} --strip-components=1
      mkdir -p ${root}/skills/btw
      cp -- ${inputs.pi-btw}/skills/btw/SKILL.md ${root}/skills/btw/SKILL.md
      cmp ${inputs.pi-btw}/extensions/btw.ts ${root}/extensions/btw.ts
    '';
  };

  pi-ponytail = mkCopyRoot {
    pname = members.ponytail.attrName;
    version = members.ponytail.version;
    install = root: ''
      cp -R -- ${inputs.ponytail}/pi-extension ${inputs.ponytail}/hooks \
        ${inputs.ponytail}/skills ${root}/
      cp -- ${inputs.ponytail}/package.json ${inputs.ponytail}/LICENSE \
        ${inputs.ponytail}/README.md ${root}/
    '';
  };

  pi-agent-browser-native = mkCopyRoot {
    pname = members.browser.attrName;
    version = members.browser.version;
    install = root: ''
      tar -xzf ${releaseTarballs.pi-agent-browser-native} -C ${root} \
        --strip-components=1
    '';
  };

  pi-cache-optimizer = mkCopyRoot {
    pname = members.cache-optimizer.attrName;
    version = members.cache-optimizer.version;
    install = root: ''
      tar -xzf ${releaseTarballs.pi-cache-optimizer} -C ${root} --strip-components=1
      ${python3}/bin/python3 - ${root}/index.ts <<'PY'
      from pathlib import Path
      import sys

      source = Path(sys.argv[1])
      text = source.read_text()
      warning = (
          'cmdCtx.ui.notify("Nix manages models.json; edit config/ai and switch '
          'the configuration instead.", "warning");'
      )

      command_marker = '} else if (subcommand === "fix") {\n        if (!model) {'
      command_replacement = (
          '} else if (subcommand === "fix") {\n'
          f'        {warning}\n'
          '        return;\n\n'
          '        if (!model) {'
      )
      menu_marker = (
          '} else if (choice === menuOptions[5]) {\n'
          '            // Fix — auto-fix compat issues'
      )
      menu_replacement = (
          '} else if (choice === menuOptions[5]) {\n'
          f'            {warning}\n'
          '            return;\n\n'
          '            // Fix — auto-fix compat issues'
      )
      replacements = {
          command_marker: command_replacement,
          menu_marker: menu_replacement,
          '"Fix — Auto-fix compat issues (writes models.json)"':
              '"Fix — Disabled because Nix manages models.json"',
          'diagnosis.push("  fix     — Auto-fix compat issues (writes models.json, requires UI)");':
              'diagnosis.push("  fix     — Disabled because Nix manages models.json");',
      }
      for old, new in replacements.items():
          if text.count(old) != 1:
              raise SystemExit(f"unexpected pi-cache-optimizer seam: {old.splitlines()[0]}")
          text = text.replace(old, new)

      profile_docs = """ *   3. LiteLLM / OneAPI / NewAPI / VoAPI — baseUrl or provider matching litellm,
       *      oneapi, one-api, newapi, new-api, voapi, vo-api (self-hosted aggregation)
       *   4. Generic third-party OpenAI-compatible proxy — any openai-completions model
       *      with a non-official base URL that does not match a higher-profile above."""
      generic_docs = """ *   3. Generic third-party OpenAI-compatible proxy — any openai-completions model
       *      with a non-official base URL that does not match a higher-profile above."""
      aggregation_start = "  // ── 3. LiteLLM / OneAPI / NewAPI / VoAPI (self-hosted aggregation) ──"
      generic_start = "  // ── 4. Generic third-party OpenAI-compatible proxy ─────────────────"
      if text.count(profile_docs) != 1:
          raise SystemExit("unexpected cache-optimizer router profile documentation")
      if text.count(aggregation_start) != 1 or text.count(generic_start) != 1:
          raise SystemExit("unexpected cache-optimizer aggregation diagnostic")
      text = text.replace(profile_docs, generic_docs)
      start = text.index(aggregation_start)
      end = text.index(generic_start, start)
      text = text[:start] + generic_start.replace("4.", "3.") + text[end + len(generic_start):]

      text = text.replace("Edit $" + "{modelsJsonPath}", "Update config/ai")
      text = text.replace(
          "Edit $" + "{getModelsJsonDisplayPath()} and run /reload.",
          "Update config/ai and switch the configuration.",
      )
      text = text.replace(
          "- Add only cache/routing compat overrides in $" + "{getModelsJsonDisplayPath()}.",
          "- Add cache/routing compat overrides in config/ai, then switch the configuration.",
      )
      text = text.replace(
          "Manual workaround: add a provider-level headers.User-Agent override in $" + "{getModelsJsonDisplayPath()}",
          "Manual workaround: add a provider-level headers.User-Agent override in config/ai",
      )
      text = text.replace(
          "Run /cache-optimizer fix",
          "Update config/ai and switch the configuration",
      )
      text = text.replace(
          "run /cache-optimizer fix",
          "update config/ai and switch the configuration",
      )
      text = text.replace(
          "/cache-optimizer fix will not auto-write headers",
          "the extension will not auto-write headers; update config/ai instead",
      )
      source.write_text(text)
      PY
      rm ${root}/README.md ${root}/README.zh-CN.md
    '';
  };

  pi-blackhole = mkCopyRoot {
    pname = members.blackhole.attrName;
    version = members.blackhole.version;
    install = root: ''
      tar -xzf ${releaseTarballs.pi-blackhole} -C ${root} --strip-components=1
    '';
  };

  pi-caveman = mkCopyRoot {
    pname = members.caveman.attrName;
    version = members.caveman.version;
    install = root: ''
      tar -xzf ${releaseTarballs.pi-caveman} -C ${root} --strip-components=1
      ${python3}/bin/python3 - ${root}/extensions/caveman.ts <<'PY'
      from pathlib import Path
      import sys

      source = Path(sys.argv[1])
      text = source.read_text()
      signature = '\tfunction syncStatus(ctx: Pick<ExtensionContext, "ui">) {'
      marker = "\n\t// -- Restore state on session load --"
      if text.count(signature) != 1 or text.count(marker) != 1:
          raise SystemExit("unexpected caveman status renderer")
      start = text.index(signature)
      end = text.index(marker, start)
      replacement = (
          '\tfunction syncStatus(ctx: Pick<ExtensionContext, "ui">) {\n'
          '\t\tstopAnimation();\n'
          '\t\tctx.ui.setStatus("caveman", undefined);\n'
          '\t}\n'
      )
      source.write_text(text[:start] + replacement + text[end:])
      PY
    '';
  };

  pi-copy-message = mkCopyRoot {
    pname = members.copy-message.attrName;
    version = members.copy-message.version;
    install = root: ''
      tar -xzf ${releaseTarballs.pi-copy-message} -C ${root} --strip-components=1
      ${python3}/bin/python3 - ${root}/extensions/copy-message.ts <<'PY'
      from pathlib import Path
      import sys

      source = Path(sys.argv[1])
      text = source.read_text()

      old_import = 'import { spawnSync } from "node:child_process";'
      new_import = 'import { copyToClipboard } from "@earendil-works/pi-coding-agent";'
      if text.count(old_import) != 1:
          raise SystemExit("unexpected pi-copy-message clipboard import")
      text = text.replace(old_import, new_import)

      start_marker = "type ClipboardCommand = {"
      end_marker = "function isToolMessage(message: CopyableMessage): boolean {"
      if text.count(start_marker) != 1 or text.count(end_marker) != 1:
          raise SystemExit("unexpected pi-copy-message clipboard implementation")
      start = text.index(start_marker)
      end = text.index(end_marker, start)
      text = text[:start] + text[end:]

      replacements = {
          'function copySelectedMessage(ctx: Pick<ExtensionCommandContext, "ui">, selected: CopyableMessage, text = selected.text) {\n\tconst error = copyToClipboard(text);\n\tif (error) {\n\t\tctx.ui.notify(error, "error");\n\t\treturn;\n\t}\n\n\tctx.ui.notify(copyNotificationText(selected), "info");\n}':
              'async function copySelectedMessage(ctx: Pick<ExtensionCommandContext, "ui">, selected: CopyableMessage, text = selected.text) {\n\ttry {\n\t\tawait copyToClipboard(text);\n\t} catch (error) {\n\t\tctx.ui.notify(error instanceof Error ? error.message : "Failed to copy to clipboard", "error");\n\t\treturn;\n\t}\n\n\tctx.ui.notify(copyNotificationText(selected), "info");\n}',
          'function copyMostRecentUserMessage(ctx: Pick<ExtensionCommandContext, "sessionManager" | "ui">, format: CopyFormat) {':
              'async function copyMostRecentUserMessage(ctx: Pick<ExtensionCommandContext, "sessionManager" | "ui">, format: CopyFormat) {',
          '\tcopySelectedMessage(ctx, result.message, formatMessageForCopy(result.message, format));':
              '\tawait copySelectedMessage(ctx, result.message, formatMessageForCopy(result.message, format));',
          '\t\t\t\tif (latestVisible) copySelectedMessage(ctx, latestVisible, formatMessageForCopy(latestVisible, parsedArgs.format));':
              '\t\t\t\tif (latestVisible) await copySelectedMessage(ctx, latestVisible, formatMessageForCopy(latestVisible, parsedArgs.format));',
          '\t\t\t\tcopySelectedMessage(ctx, selected, formatMessageForCopy(selected, parsedArgs.format));':
              '\t\t\t\tawait copySelectedMessage(ctx, selected, formatMessageForCopy(selected, parsedArgs.format));',
          '\t\t\tcopySelectedMessage(ctx, selected.message, selected.text);':
              '\t\t\tawait copySelectedMessage(ctx, selected.message, selected.text);',
          '\t\t\tcopyMostRecentUserMessage(ctx, parseCopyArgs(args).format);':
              '\t\t\tawait copyMostRecentUserMessage(ctx, parseCopyArgs(args).format);',
      }
      for old, new in replacements.items():
          if text.count(old) != 1:
              raise SystemExit(f"unexpected pi-copy-message async seam: {old.splitlines()[0]}")
          text = text.replace(old, new)

      source.write_text(text)
      PY
    '';
  };

  pi-goal-x = mkCopyRoot {
    pname = members.goal.attrName;
    version = members.goal.version;
    install = root: ''
      tar -xzf ${releaseTarballs.pi-goal-x} -C ${root} --strip-components=1
      substituteInPlace ${root}/extensions/goal-core.ts \
        --replace-fail \
          'return `''${prefix}: ''${statusLabel(goal)}''${usage} - ''${truncateText(goal.objective, 60)}`;' \
          'return `''${prefix}: ''${statusLabel(goal)}''${usage}`;'
    '';
  };

  pi-multi-pass = mkCopyRoot {
    pname = members.multi-pass.attrName;
    version = members.multi-pass.version;
    install = root: ''
      tar -xzf ${releaseTarballs.pi-multi-pass} -C ${root} --strip-components=1
    '';
  };

  pi-model-router = mkCopyRoot {
    pname = members.router.attrName;
    version = members.router.version;
    install = root: ''
      tar -xzf ${releaseTarballs.pi-model-router} -C ${root} \
        --strip-components=1
    '';
  };

  pi-rewind = mkCopyRoot {
    pname = members.rewind.attrName;
    version = members.rewind.version;
    install = root: ''
      tar -xzf ${releaseTarballs.pi-rewind} -C ${root} --strip-components=1
      substituteInPlace ${root}/src/ui.ts \
        --replace-fail \
          '/** Update footer status with checkpoint count */' \
          '/** Keep rewind out of the footer. */' \
        --replace-fail \
          $'  const theme = ctx.ui.theme;\n  const count = state.checkpoints.size;\n  ctx.ui.setStatus(\n    STATUS_KEY,\n    theme.fg("dim", "◆ ") + theme.fg("muted", `''${count} checkpoint''${count === 1 ? "" : "s"}`),\n  );' \
          '  ctx.ui.setStatus(STATUS_KEY, undefined);'
    '';
  };

  pi-trace-extension = mkCopyRoot {
    pname = members.trace.attrName;
    version = members.trace.version;
    install = root: ''
      tar -xzf ${releaseTarballs.pi-trace-extension} -C ${root} --strip-components=1
      ${python3}/bin/python3 - \
        ${root}/extensions/trace/index.ts ${python3}/bin/python3 \
        ${root}/extensions/trace/trace_to_html.py <<'PY'
      from pathlib import Path
      import sys

      source = Path(sys.argv[1])
      python = sys.argv[2]
      renderer = Path(sys.argv[3])
      text = source.read_text()
      anchor = "export default function (pi: ExtensionAPI) {"
      sanitizer = r"""
      const SECRET_KEY = /^(password|passphrase|secret|(?:aws[-_]?)?secret[-_]?access[-_]?key|(?:x[-_]?)?api[-_]?key|access[-_]?token|refresh[-_]?token|auth(?:orization)?|proxy[-_]?authorization|auth[-_]?token|bearer|client[-_]?secret|private[-_]?key|cookie|set[-_]?cookie|token)$/i;

      function sanitizeTraceValue(value: unknown, depth = 0, seen = new WeakSet<object>()): unknown {
        if (depth > 12) return "[max depth]";
        if (value === undefined) return undefined;
        if (typeof value === "string") {
          return value.length > 8000 ? `''${value.slice(0, 8000)}…[truncated]` : value;
        }
        if (typeof value === "number") return Number.isFinite(value) ? value : null;
        if (typeof value === "bigint") return value.toString();
        if (typeof value === "function" || typeof value === "symbol") return undefined;
        if (value === null || typeof value === "boolean") return value;
        if (Array.isArray(value)) {
          return value.map((item) => sanitizeTraceValue(item, depth + 1, seen));
        }
        if (typeof value === "object") {
          if (seen.has(value)) return "[circular]";
          seen.add(value);
          const result: Record<string, unknown> = {};
          for (const [key, item] of Object.entries(value)) {
            result[key] = SECRET_KEY.test(key)
              ? "[REDACTED]"
              : sanitizeTraceValue(item, depth + 1, seen);
          }
          seen.delete(value);
          return result;
        }
        return null;
      }

      """
      if text.count(anchor) != 1:
          raise SystemExit("unexpected pi-trace extension entrypoint")
      text = text.replace(anchor, sanitizer + anchor)

      replacements = {
          'const PYTHON_BIN = process.env.PI_TRACE_PYTHON || "python3";':
              f'const PYTHON_BIN = process.env.PI_TRACE_PYTHON || "{python}";',
          'writeStream.write(JSON.stringify(event) + "\\n");':
              'writeStream.write(JSON.stringify(sanitizeTraceValue(event)) + "\\n");',
          'const r = JSON.stringify(event.result);':
              'const r = JSON.stringify(sanitizeTraceValue(event.result));',
          'fs.mkdirSync(sessionDir, { recursive: true });':
              'fs.mkdirSync(sessionDir, { recursive: true, mode: 0o700 });\n'
              '\t\t\tfs.chmodSync(sessionDir, 0o700);',
          'writeStream = fs.createWriteStream(traceFile, { flags: "a" });':
              'const traceFd = fs.openSync(traceFile, "a", 0o600);\n'
              '\t\t\tfs.fchmodSync(traceFd, 0o600);\n'
              '\t\t\twriteStream = fs.createWriteStream(traceFile, { fd: traceFd, autoClose: true });',
          'sessionDir = path.join(TRACE_DIR, sessionId);':
              'fs.mkdirSync(TRACE_DIR, { recursive: true, mode: 0o700 });\n'
              '\t\t\tfs.chmodSync(TRACE_DIR, 0o700);\n'
              '\t\t\tsessionDir = path.join(TRACE_DIR, sessionId);',
          'if (ret && typeof (ret as any).then === "function") {\n'
          '\t\t\t\t\t(ret as Promise<void>).catch(rejErr =>\n'
          '\t\t\t\t\t\tmarkDisabled(`async handler ''${name} rejected`, rejErr));\n'
          '\t\t\t\t}':
              'if (ret && typeof (ret as any).then === "function") {\n'
              '\t\t\t\t\treturn (ret as Promise<void>).catch(rejErr =>\n'
              '\t\t\t\t\t\tmarkDisabled(`async handler ''${name} rejected`, rejErr));\n'
              '\t\t\t\t}',
          'pi.on("session_shutdown", safeHandler("session_shutdown", () => {\n'
          '\t\twriteEvent(baseEvent({ type: "session_shutdown" }));\n'
          '\t\t// H1 修复：立即置 null 屏蔽后续写入，避免 renderHtml(sync) 阻塞期间被\n'
          '\t\t// 其他 handler（如未收尾的 tool_end）写到已 end() 的 stream 上触发\n'
          '\t\t// ERR_STREAM_WRITE_AFTER_END → uncaughtException 崩 pi\n'
          '\t\tconst stream = writeStream;\n'
          '\t\twriteStream = null;\n'
          '\t\ttry { stream?.end(); } catch { /* ignore */ }\n'
          '\t\t// 兜底：session 退出时同步生成一次 HTML（不打开浏览器）\n'
          '\t\ttry { renderHtml({ open: false, sync: true }); } catch { /* silent */ }\n'
          '\t}));':
              'pi.on("session_shutdown", safeHandler("session_shutdown", async () => {\n'
              '\t\twriteEvent(baseEvent({ type: "session_shutdown" }));\n'
              '\t\tconst stream = writeStream;\n'
              '\t\twriteStream = null;\n'
              '\t\tif (stream) {\n'
              '\t\t\tawait new Promise<void>((resolve) => {\n'
              '\t\t\t\tstream.once("finish", resolve);\n'
              '\t\t\t\tstream.once("close", resolve);\n'
              '\t\t\t\ttry { stream.end(); } catch { resolve(); }\n'
              '\t\t\t});\n'
              '\t\t}\n'
              '\t\tconst rendered = renderHtml({ open: false, sync: true });\n'
              '\t\tif (!rendered.ok) console.error(`[pi-trace] shutdown render failed: ''${rendered.error}`);\n'
              '\t}));',
          'console.log(`[pi-trace] extension loaded → ''${TRACE_DIR} · use /trace to render HTML`);':
              "",
          '\t// /trace 命令：立刻渲染并打开':
              '\tconst flushTraceStream = async () => {\n'
              '\t\tconst stream = writeStream;\n'
              '\t\tif (!stream || stream.destroyed) return;\n'
              '\t\tawait new Promise<void>((resolve) => {\n'
              '\t\t\ttry { stream.write("", resolve); } catch { resolve(); }\n'
              '\t\t});\n'
              '\t};\n\n'
              '\t// /trace 命令：立刻渲染并打开',
          '\t\thandler: async (args, ctx) => {\n'
          '\t\t\tconst sub = (args || "").trim().toLowerCase();':
              '\t\thandler: async (args, ctx) => {\n'
              '\t\t\tconst sub = (args || "").trim().toLowerCase();\n'
              '\t\t\tawait flushTraceStream();',
          'const child = spawn(PYTHON_BIN, args, { stdio: "ignore", detached: true });\n\t\t\t\tchild.unref();':
              'const child = spawn(PYTHON_BIN, args, { stdio: "ignore", detached: true });\n'
              '\t\t\t\tchild.on("error", () => {});\n\t\t\t\tchild.unref();',
          'spawn(cmd, [filePath], { stdio: "ignore", detached: true, shell: platform === "win32" }).unref();':
              'const child = spawn(cmd, [filePath], { stdio: "ignore", detached: true, shell: platform === "win32" });\n'
              '\t\t\tchild.on("error", () => {});\n\t\t\tchild.unref();',
      }
      expected_counts = {
          'const child = spawn(PYTHON_BIN, args, { stdio: "ignore", detached: true });\n\t\t\t\tchild.unref();': 2,
          'fs.mkdirSync(sessionDir, { recursive: true });': 2,
          'writeStream = fs.createWriteStream(traceFile, { flags: "a" });': 2,
      }
      for old, new in replacements.items():
          expected = expected_counts.get(old, 1)
          if text.count(old) != expected:
              raise SystemExit(f"unexpected pi-trace seam count for {old.splitlines()[0]}")
          text = text.replace(old, new)
      source.write_text(text)

      renderer_text = renderer.read_text()
      renderer_replacements = {
          'import json, sys, html, re, time\nfrom pathlib import Path':
              'import json, sys, html, os, re, time\nfrom pathlib import Path\n\n'
              'os.umask(0o077)',
          '    out.write_text(render_dashboard(summaries), encoding="utf-8")':
              '    out.write_text(render_dashboard(summaries), encoding="utf-8")\n'
              '    out.chmod(0o600)',
          '    output.write_text(out_html, encoding="utf-8")':
              '    output.write_text(out_html, encoding="utf-8")\n'
              '    output.chmod(0o600)',
      }
      for old, new in renderer_replacements.items():
          if renderer_text.count(old) != 1:
              raise SystemExit(f"unexpected pi-trace renderer seam: {old}")
          renderer_text = renderer_text.replace(old, new)
      renderer.write_text(renderer_text)
      PY
      find ${root} -type f -name '*.pyc' -delete
      find ${root} -type d -name __pycache__ -empty -delete
    '';
  };

  pi-rtk-optimizer = mkCopyRoot {
    pname = members.rtk-optimizer.attrName;
    version = members.rtk-optimizer.version;
    install = root: ''
      tar -xzf ${releaseTarballs.pi-rtk-optimizer} -C ${root} --strip-components=1
    '';
  };

  pi-cymbal = mkCopyRoot {
    pname = members.cymbal-extension.attrName;
    version = members.cymbal-extension.version;
    install = root: ''
      tar -xzf ${releaseTarballs.pi-cymbal} -C ${root} --strip-components=1
    '';
  };

  mkBinaryTool =
    pname: member:
    let
      archive =
        if stdenv.hostPlatform.isDarwin then
          releaseTarballs.${member.attrName}
        else
          fetchurl member.artifacts.${stdenv.hostPlatform.system}.args;
    in
    runCommand "${pname}-${member.version}"
      {
        passthru.version = member.version;
        meta.mainProgram = pname;
      }
      ''
        mkdir -p "$out/bin" "$TMPDIR/unpack"
        tar -xzf ${archive} -C "$TMPDIR/unpack"
        binary=$(${findutils}/bin/find "$TMPDIR/unpack" -type f -name ${lib.escapeShellArg pname} -print -quit)
        test -n "$binary"
        install -m 0755 "$binary" "$out/bin/${pname}"
        ${lib.optionalString stdenv.hostPlatform.isLinux ''
          if ${patchelf}/bin/patchelf --print-interpreter "$out/bin/${pname}" >/dev/null 2>&1; then
            ${patchelf}/bin/patchelf \
              --set-interpreter ${stdenv.cc.bintools.dynamicLinker} \
              --set-rpath ${lib.makeLibraryPath [ stdenv.cc.cc.lib ]} \
              "$out/bin/${pname}"
          fi
        ''}
      '';

  rtk = mkBinaryTool "rtk" supportSources.rtk;
  cymbal = mkBinaryTool "cymbal" supportSources.cymbal;

  agent-browser =
    runCommand "agent-browser-${supportSources.agent-browser.version}"
      {
        nativeBuildInputs = [
          findutils
          makeWrapper
        ]
        ++ lib.optional stdenv.hostPlatform.isLinux patchelf;
        passthru.version = supportSources.agent-browser.version;
        meta.mainProgram = "agent-browser";
      }
      ''
        package="$out/libexec/agent-browser"
        mkdir -p "$package" "$out/bin"
        tar -xzf ${releaseTarballs.agent-browser} -C "$package" --strip-components=1

        ${
          if stdenv.hostPlatform.isDarwin then
            ''
              binary="$package/bin/agent-browser-darwin-${
                if stdenv.hostPlatform.isAarch64 then "arm64" else "x64"
              }"
              browser_executable=$(${findutils}/bin/find -L ${playwright-driver.browsers} -type f \
                -path '*/Google Chrome for Testing.app/Contents/MacOS/Google Chrome for Testing' \
                -print -quit)
            ''
          else
            ''
              binary="$package/bin/agent-browser-linux-${
                if stdenv.hostPlatform.isAarch64 then "arm64" else "x64"
              }"
              browser_executable=${chromium}/bin/chromium
            ''
        }
        chmod 0755 "$binary"
        ${lib.optionalString stdenv.hostPlatform.isLinux ''
          patchelf --set-interpreter ${stdenv.cc.bintools.dynamicLinker} \
            --set-rpath ${lib.makeLibraryPath [ stdenv.cc.cc.lib ]} "$binary"
        ''}
        test -x "$binary"
        test -x "$browser_executable"
        makeWrapper "$binary" "$out/bin/agent-browser" \
          --set-default AGENT_BROWSER_EXECUTABLE_PATH "$browser_executable"
      '';

  roots = lib.mapAttrs (_: member: packageRoot member.package member.attrName) members;
  projection = {
    packages = map (
      id:
      let
        member = members.${id};
      in
      {
        name = member.publicName;
        version = member.projectionVersion or member.version;
        extensions = [ "${roots.${id}}/${member.extension}" ];
      }
      // lib.optionalAttrs (member ? skills) {
        skills = map (path: "${roots.${id}}/${path}") member.skills;
      }
      // lib.optionalAttrs (member ? prompts) {
        prompts = map (path: "${roots.${id}}/${path}") member.prompts;
      }
    ) activeOrder;
  };
  memberPackages = lib.listToAttrs (
    map (id: lib.nameValuePair members.${id}.attrName members.${id}.package) order
  );
  supportPackages = lib.mapAttrs' (
    _: member: lib.nameValuePair member.attrName member.package
  ) supportSources;
  galleryPackages = memberPackages // supportPackages;
  galleryIdentifier = id: lib.replaceStrings [ "-" ] [ "_" ] id;
  galleryImports = lib.concatMapStringsSep "\n" (
    id:
    "import ${galleryIdentifier id} from ${builtins.toJSON "${roots.${id}}/${members.${id}.extension}"};"
  ) activeOrder;
  galleryRegistrations = lib.concatMapStringsSep ",\n" (
    id: "            [${builtins.toJSON id}, ${galleryIdentifier id}]"
  ) activeOrder;

  pi-gallery =
    runCommand "pi-gallery"
      {
        passthru = {
          inherit
            manifest
            projection
            roots
            ;
          packages = galleryPackages;
        };
      }
      ''
        root="$out/share/pi-gallery"
        mkdir -p "$root"
        cat > "$root/index.ts" <<'TS'
        import { writeFileSync } from "node:fs";

        ${galleryImports}

        export default async function nixGallery(pi: unknown) {
          process.env.PONYTAIL_HIDE_STATUS = "1";
          process.env.PI_LENS_DISABLE_LSP_INSTALL = "1";
          process.env.PI_LENS_AUTO_INSTALL = "0";

          const toolOwnersFile = process.env.PI_GALLERY_TOOL_OWNERS_FILE;
          const toolOwners: Record<string, string[]> = {};
          for (const [owner, extension] of [
        ${galleryRegistrations}
          ] as const) {
            const extensionApi = toolOwnersFile
              ? new Proxy(pi as object, {
                  get(target, property) {
                    const value = Reflect.get(target, property, target);
                    if (property !== "registerTool") {
                      return typeof value === "function" ? value.bind(target) : value;
                    }
                    if (typeof value !== "function") {
                      throw new Error("Pi registerTool API is not callable");
                    }
                    return (...args: unknown[]) => {
                      const tool = args[0] as { name?: unknown } | undefined;
                      if (typeof tool?.name !== "string") {
                        throw new Error(`Gallery member ''${owner} registered an unnamed tool`);
                      }
                      (toolOwners[tool.name] ??= []).push(owner);
                      return Reflect.apply(value, target, args);
                    };
                  },
                  set(target, property, value) {
                    return Reflect.set(target, property, value, target);
                  },
                })
              : pi;
            await extension(extensionApi as never);
          }

          const extensionApi = pi as { on: (event: string, handler: () => unknown) => void };
          extensionApi.on("resources_discover", () => ({
            skillPaths: ${builtins.toJSON (lib.concatMap (item: item.skills or [ ]) projection.packages)},
            promptPaths: ${builtins.toJSON (lib.concatMap (item: item.prompts or [ ]) projection.packages)},
          }));
          if (toolOwnersFile) {
            extensionApi.on("session_start", () => {
              writeFileSync(toolOwnersFile, JSON.stringify(toolOwners));
            });
          }
        }
        TS
        cat > "$root/projection.json" <<'JSON'
        ${builtins.toJSON projection}
        JSON
      '';
in
assert normalizationContractValid;
assert sourceCatalogComplete;
assert normalizationTargets == lockBearingTargets;
assert normalizationTargets == galleryLockBearingTargets;
assert
  inputs.agent-browser-source.rev == manifest.sourceCatalog.agent-browser-source.source.args.rev;
assert
  inputs.agent-browser-source.narHash
  == manifest.sourceCatalog.agent-browser-source.source.args.narHash;
assert inputs.pi-btw.rev == members.btw.artifacts.flakeInput.args.rev;
assert inputs.pi-btw.narHash == members.btw.artifacts.flakeInput.args.narHash;
assert inputs.ponytail.rev == members.ponytail.source.args.rev;
assert inputs.ponytail.narHash == members.ponytail.source.args.narHash;
galleryPackages // { inherit pi-gallery; }
