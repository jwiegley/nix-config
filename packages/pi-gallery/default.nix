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
        pi-lens
        pi-loop
        pi-mem
        pi-model-router
        pi-multi-pass
        pi-ponytail
        pi-provider-llama-swap
        pi-provider-omlx
        pi-rewind
        pi-smart-fetch
        pi-smart-web-search
        pi-subagents
        pi-trace-extension
        pi-usage-extension
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
  # This eval-time validator deliberately duplicates the policy rules that
  # normalize-manifest.jq enforces at build time — the two have distinct,
  # load-bearing roles. The jq is the executor: it validates and applies the
  # policy whenever a target is normalized, but only for the target at hand,
  # and only when a derivation is actually built. This assert is the
  # whole-contract gate: it runs on every evaluation, including
  # `nix flake check --no-build` — bin/update's pre-sign validation — so a
  # policy corruption can never be captured in a signed commit. A 2026-08
  # attempt to delete it in favor of the jq alone was adversarially
  # rejected on exactly those two gaps.
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
      forceEmptyCache ? false,
      testBundleEntry ? null,
      prepareBundle ? (_root: ""),
      nodejs ? buildPackages.nodejs_22,
    }:
    buildNpmPackage {
      inherit
        forceEmptyCache
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
  memSource = mkMemberReleaseSource members.mem { };
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
    prepareBundle = root: ''
      ${buildPackages.patch}/bin/patch --force --fuzz=0 --no-backup-if-mismatch \
        --directory=${root} --strip=1 \
        < ${./patches/pi-markdown-preview-bounded-history.patch}
    '';
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
    prepareBundle = root: ''
      ${buildPackages.patch}/bin/patch --force --fuzz=0 --no-backup-if-mismatch \
        --directory=${root} --strip=1 \
        < ${./patches/pi-subagents-bounded-history.patch}
      patch_artifact="$(
        find ${root}/src -type f \( -name '*.orig' -o -name '*.rej' \) \
          -print -quit
      )"
      if [ -n "$patch_artifact" ]; then
        echo "pi-subagents patch did not apply exactly: $patch_artifact" >&2
        exit 1
      fi
    '';
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
  pi-mem = mkNpmPackageRoot {
    pname = members.mem.attrName;
    version = members.mem.version;
    src = memSource;
    npmDepsHash = members.mem.hashes.npmDepsHash;
    forceEmptyCache = true;
    prepareBundle = root: ''
      ${buildPackages.patch}/bin/patch --force --fuzz=0 --no-backup-if-mismatch \
        --directory=${root} --strip=1 \
        < ${./patches/pi-mem-private-state.patch}
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
      chmod -R u+w ${root}
      substituteInPlace ${root}/extensions/index.ts \
        --replace-fail \
          'if (entries[index]?.role === "assistant") {' \
          'if ((entries[index]?.message ?? entries[index])?.role === "assistant") {' \
        --replace-fail \
          'return messageToText(entries[index]);' \
          'return messageToText(entries[index]?.message ?? entries[index]);'
      ${buildPackages.patch}/bin/patch --force --fuzz=0 --no-backup-if-mismatch \
        --directory=${root} --strip=1 \
        < ${./patches/pi-loop-bounded-history.patch}
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
      ${buildPackages.patch}/bin/patch --force --fuzz=0 --no-backup-if-mismatch \
        --directory=${root} --strip=1 \
        < ${./patches/pi-btw-overlay-escape.patch}
      ${buildPackages.patch}/bin/patch --force --fuzz=0 --no-backup-if-mismatch \
        --directory=${root} --strip=1 \
        < ${./patches/pi-btw-bounded-history.patch}
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
      chmod -R u+w ${root}/pi-extension
      ${buildPackages.patch}/bin/patch --force --fuzz=0 --no-backup-if-mismatch \
        --directory=${root} --strip=1 \
        < ${./patches/pi-ponytail-bounded-history.patch}
    '';
  };

  pi-agent-browser-native = mkCopyRoot {
    pname = members.browser.attrName;
    version = members.browser.version;
    install = root: ''
      tar -xzf ${releaseTarballs.pi-agent-browser-native} -C ${root} \
        --strip-components=1
      ${buildPackages.patch}/bin/patch --force --fuzz=0 --no-backup-if-mismatch \
        --directory=${root} --strip=1 \
        < ${./patches/pi-agent-browser-bounded-history.patch}
    '';
  };

  pi-usage-extension = mkCopyRoot {
    pname = members.usage.attrName;
    version = members.usage.version;
    install = root: ''
      tar -xzf ${releaseTarballs.pi-usage-extension} -C ${root} --strip-components=1
      substituteInPlace ${root}/index.ts \
        --replace-fail \
          'writeFileSync(path, content);' \
          'writeFileSync(path, content, { encoding: "utf8", mode: 0o600, flag: "wx" });'
      cp -- ${./patches/pi-usage-stream-json.ts} ${root}/stream-json.ts
      cp -- ${./patches/pi-usage-bounded-store.ts} ${root}/bounded-store.ts
      ${buildPackages.patch}/bin/patch --force --fuzz=0 --no-backup-if-mismatch \
        --directory=${root} --strip=1 \
        < ${./patches/pi-usage-bounded-history.patch}
    '';
  };

  pi-cache-optimizer = mkCopyRoot {
    pname = members.cache-optimizer.attrName;
    version = members.cache-optimizer.version;
    install = root: ''
      tar -xzf ${releaseTarballs.pi-cache-optimizer} -C ${root} --strip-components=1
      ${python3}/bin/python3 - ${root}/index.ts <<'PY'
      import hashlib
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

      generic_docs = """ *   4. Generic third-party OpenAI-compatible proxy — any openai-completions model
       *      with a non-official base URL that does not match a higher-profile above."""
      generic_start = "  // ── 4. Generic third-party OpenAI-compatible proxy ─────────────────"
      for marker, prior, expected in (
          (generic_docs, " *   3. ", "0845a84222d192546c93b37b7cf92acfd08805c517cd79b950d0d449f123fb80"),
          (generic_start, "  // ── 3. ", "ba6cd49840abce00beda5f8f1515ca28e8dc9284903061abadc65bdf50e9d8cb"),
      ):
          if text.count(marker) != 1:
              raise SystemExit("unexpected cache-optimizer aggregation seam")
          end = text.index(marker)
          start = text.rfind(prior, 0, end)
          block = text[start:end].encode() if start >= 0 else b""
          if hashlib.sha256(block).hexdigest() != expected:
              raise SystemExit("unexpected cache-optimizer aggregation ordering")
          text = text[:start] + marker.replace("4.", "3.", 1) + text[end + len(marker):]

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
      if [ -e ${root}/src/om/compaction-threshold.ts ]; then
        echo "pi-blackhole now provides compaction-threshold.ts; review the local patch" >&2
        exit 1
      fi
      cp -- ${./patches/pi-blackhole-compaction-threshold.ts} \
        ${root}/src/om/compaction-threshold.ts
      ${python3}/bin/python3 - \
        ${root}/src/om/compaction-trigger.ts \
        ${root}/src/commands/memory.ts \
        ${root}/src/om/configure-overlay.ts <<'PY'
      from pathlib import Path
      import sys

      trigger = Path(sys.argv[1])
      trigger_text = trigger.read_text()

      trigger_replacements = {
          'import { RETRYABLE_ERROR_RE } from "./retryable-error.js";':
              'import { RETRYABLE_ERROR_RE } from "./retryable-error.js";\nimport { resolveCompactionPressure } from "./compaction-threshold.js";',
          """\tconst entries = ctx.sessionManager.getBranch() as Entry[];
      \tconst tokens = rawTokensSinceLastCompaction(entries);
      \tif (tokens < runtime.config.compactAfterTokens) {
      \t\t// Pressure relieved (a compaction ran) — lift any failure suspension.
      \t\truntime.midRunCompactionSuspended = false;
      \t\treturn;
      \t}""":
              """\tconst { tokens, threshold } = resolveCompactionPressure(
      \t\tctx.getContextUsage?.(),
      \t\t() => rawTokensSinceLastCompaction(ctx.sessionManager.getBranch() as Entry[]),
      \t\truntime.config.compactAfterTokens,
      \t);
      \tif (tokens < threshold) {
      \t\t// Pressure relieved (a compaction ran) — lift any failure suspension.
      \t\truntime.midRunCompactionSuspended = false;
      \t\treturn;
      \t}""",
          'dbg("compaction_trigger.turn_end.threshold_reached", { tokens, threshold: runtime.config.compactAfterTokens, mode });':
              'dbg("compaction_trigger.turn_end.threshold_reached", { tokens, threshold, mode });',
          """\t\tconst entries = ctx.sessionManager.getBranch() as Entry[];
      \t\tdbg("compaction_trigger.branch_check", { branchLength: entries.length, hasLastEntry: entries.length > 0, lastEntryType: entries.length > 0 ? entries[entries.length - 1].type : "none" });

      \t\tconst tokens = rawTokensSinceLastCompaction(entries);
      \t\tdbg("compaction_trigger.tokens", { tokens, compactAfterTokens: runtime.config.compactAfterTokens, branchLength: entries.length });
      \t\tif (tokens < runtime.config.compactAfterTokens) {
      \t\t\tdbg("compaction_trigger.skip", { reason: "below_threshold", tokens, threshold: runtime.config.compactAfterTokens });
      \t\t\treturn;
      \t\t}""":
              """\t\tconst { tokens, threshold, source } = resolveCompactionPressure(
      \t\t\tctx.getContextUsage?.(),
      \t\t\t() => rawTokensSinceLastCompaction(ctx.sessionManager.getBranch() as Entry[]),
      \t\t\truntime.config.compactAfterTokens,
      \t\t);
      \t\tdbg("compaction_trigger.tokens", { tokens, threshold, source });
      \t\tif (tokens < threshold) {
      \t\t\tdbg("compaction_trigger.skip", { reason: "below_threshold", tokens, threshold });
      \t\t\treturn;
      \t\t}""",
          """\t\t\tconst currentEntries = ctx.sessionManager.getBranch() as Entry[];
      \t\t\tconst currentTokens = rawTokensSinceLastCompaction(currentEntries);
      \t\t\tdbg("compaction_trigger.microtask.recheck_tokens", { currentTokens, threshold: runtime.config.compactAfterTokens, ok: currentTokens >= runtime.config.compactAfterTokens });
      \t\t\tif (currentTokens < runtime.config.compactAfterTokens) {
      \t\t\t\truntime.compactInFlight = false;
      \t\t\t\truntime.autoCompactionController = null;
      \t\t\t\tdbg("compaction_trigger.microtask.bail", { reason: "pressure_relieved", currentTokens, threshold: runtime.config.compactAfterTokens });""":
              """\t\t\tconst currentPressure = resolveCompactionPressure(
      \t\t\t\tctx.getContextUsage?.(),
      \t\t\t\t() => rawTokensSinceLastCompaction(ctx.sessionManager.getBranch() as Entry[]),
      \t\t\t\truntime.config.compactAfterTokens,
      \t\t\t);
      \t\t\tconst currentTokens = currentPressure.tokens;
      \t\t\tconst currentThreshold = currentPressure.threshold;
      \t\t\tdbg("compaction_trigger.microtask.recheck_tokens", { currentTokens, threshold: currentThreshold, ok: currentTokens >= currentThreshold });
      \t\t\tif (currentTokens < currentThreshold) {
      \t\t\t\truntime.compactInFlight = false;
      \t\t\t\truntime.autoCompactionController = null;
      \t\t\t\tdbg("compaction_trigger.microtask.bail", { reason: "pressure_relieved", currentTokens, threshold: currentThreshold });""",
      }
      for old, new in trigger_replacements.items():
          if trigger_text.count(old) != 1:
              raise SystemExit(f"unexpected pi-blackhole compaction trigger seam: {old.splitlines()[0]}")
          trigger_text = trigger_text.replace(old, new)
      trigger.write_text(trigger_text)

      memory = Path(sys.argv[2])
      memory_text = memory.read_text()
      memory_replacements = {
          'import { readPendingState } from "../om/pending.js";':
              'import { readPendingState } from "../om/pending.js";\nimport { resolveCompactionPressure } from "../om/compaction-threshold.js";',
          """\t\t\tconst compactionProgress = rawTokensSinceLastCompaction(entries);""":
              """\t\t\tconst compactionPressure = resolveCompactionPressure(
      \t\t\t\tctx.getContextUsage?.(),
      \t\t\t\trawTokensSinceLastCompaction(entries),
      \t\t\t\truntime.config.compactAfterTokens,
      \t\t\t);""",
          'Compaction:     ~''${compactionProgress.toLocaleString()} tokens` + (runtime.config.noAutoCompact ? " [auto-disabled]" : ` (triggers at ''${runtime.config.compactAfterTokens.toLocaleString()})`)':
              'Compaction:     ~''${compactionPressure.tokens.toLocaleString()} tokens` + (runtime.config.noAutoCompact ? " [auto-disabled]" : ` (triggers at ''${compactionPressure.threshold.toLocaleString()})`)',
      }
      for old, new in memory_replacements.items():
          if memory_text.count(old) != 1:
              raise SystemExit(f"unexpected pi-blackhole memory status seam: {old.splitlines()[0]}")
          memory_text = memory_text.replace(old, new)
      memory.write_text(memory_text)

      overlay = Path(sys.argv[3])
      overlay_text = overlay.read_text()
      old_field = '{ key: "compactAfterTokens", label: "Auto-compact threshold", type: "number", section: "Compaction",\n\t\thelpText: "Token count that triggers auto-compaction when reached" }'
      new_field = '{ key: "compactAfterTokens", label: "Fallback auto-compact threshold", type: "number", section: "Compaction",\n\t\thelpText: "Used only when Pi cannot report live context usage; otherwise compaction triggers at 70%" }'
      if overlay_text.count(old_field) != 1:
          raise SystemExit("unexpected pi-blackhole compaction threshold field")
      overlay.write_text(overlay_text.replace(old_field, new_field))
      PY
      ${buildPackages.patch}/bin/patch --force --fuzz=0 --no-backup-if-mismatch \
        --directory=${root} --strip=1 \
        < ${./patches/pi-blackhole-bounded-history.patch}
      cp -- ${./patches/pi-blackhole-streaming-history.ts} \
        ${root}/src/core/streaming-history.ts
      cp -- ${./patches/pi-blackhole-streaming-memory.ts} \
        ${root}/src/core/streaming-memory.ts
      ${buildPackages.patch}/bin/patch --force --fuzz=0 --no-backup-if-mismatch \
        --directory=${root} --strip=1 \
        < ${./patches/pi-blackhole-exact-recall.patch}
      ${buildPackages.patch}/bin/patch --force --fuzz=0 --no-backup-if-mismatch \
        --directory=${root} --strip=1 \
        < ${./patches/pi-blackhole-exact-memory.patch}
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
      ${buildPackages.patch}/bin/patch --force --fuzz=0 --no-backup-if-mismatch \
        --directory=${root} --strip=1 \
        < ${./patches/pi-caveman-bounded-history.patch}
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
      ${buildPackages.patch}/bin/patch --force --fuzz=0 --no-backup-if-mismatch \
        --directory=${root} --strip=1 \
        < ${./patches/pi-copy-message-bounded-history.patch}
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
      ${buildPackages.patch}/bin/patch --force --fuzz=0 --no-backup-if-mismatch \
        --directory=${root} --strip=1 \
        < ${./patches/pi-goal-x-bounded-history.patch}
      patch_artifact="$(
        find ${root} -path '*/node_modules' -prune -o \
          -type f \( -name '*.orig' -o -name '*.rej' \) -print -quit
      )"
      if [ -n "$patch_artifact" ]; then
        echo "pi-goal-x patch did not apply exactly: $patch_artifact" >&2
        exit 1
      fi
      substituteInPlace ${root}/extensions/goal.ts \
        --replace-fail \
          'export default function goalExtension(pi: ExtensionAPI): void {' \
          $'export default function goalExtension(pi: ExtensionAPI): void {\n\tif (process.env.PI_SUBAGENT_CHILD === "1") return;'
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
      ${buildPackages.patch}/bin/patch --force --fuzz=0 --no-backup-if-mismatch \
        --directory=${root} --strip=1 \
        < ${./patches/pi-model-router-bounded-history.patch}
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
      ${buildPackages.patch}/bin/patch --force --fuzz=0 --no-backup-if-mismatch \
        --directory=${root} --strip=1 \
        < ${./patches/pi-rewind-bounded-history.patch}
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
    ) order;
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
