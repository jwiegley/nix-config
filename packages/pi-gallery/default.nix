{
  buildNpmPackage,
  buildPackages,
  chromium,
  esbuild,
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
  unzip,
  writeShellScript,
}:

let
  packageRoot = package: name: "${package}/share/pi-packages/${name}";

  manifest = import ./manifest.nix {
    inherit inputs;
    packages = {
      inherit
        agent-browser
        betterwright
        cymbal
        pi-agent-browser-native
        pi-artifacts
        pi-blackhole
        pi-btw
        pi-caveman
        pi-cymbal
        pi-dynamic-workflows
        pi-goal-x
        pi-markdown-preview
        pi-retry
        pi-rtk-optimizer
        pi-hashline-edit-pro
        pi-insights
        pi-lens
        pi-model-router
        pi-multi-pass
        pi-ponytail
        pi-provider-litellm
        pi-rewind
        pi-scroll
        pi-smart-fetch
        pi-smart-web-search
        pi-subagents
        rtk
        ;
    };
  };
  inherit (manifest) members order supportSources;
  sourceRecords = members // supportSources;
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
      dropPeerMetadata ? true,
      hashline ? false,
      lens ? false,
      subagents ? false,
      smartFetch ? false,
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

        ${jq}/bin/jq '
          del(.devDependencies)
          ${lib.optionalString dropPeerMetadata "| del(.peerDependencies, .peerDependenciesMeta)"}
          ${lib.optionalString hashline ''
            | del(.dependencies["better-sqlite3"], .allowScripts)
          ''}
          ${lib.optionalString lens ''
            | del(.dependencies["@earendil-works/pi-tui"], .dependencies.typebox)
          ''}
          ${lib.optionalString smartFetch ''
            | del(.dependencies["@earendil-works/pi-tui"], .dependencies["@sinclair/typebox"])
          ''}
          ${lib.optionalString subagents "| del(.dependencies.typebox)"}
        ' "$out/package.json" > "$out/package.json.normalized"
        mv "$out/package.json.normalized" "$out/package.json"
        cp ${lockFile} "$out/package-lock.json"

        ${lib.optionalString hashline ''
          substituteInPlace "$out/src/hash-store.ts" \
            --replace-fail \
              'async function tryLoadBetter(): Promise<boolean> {' \
              $'async function tryLoadBetter(): Promise<boolean> {\n  // Bun standalone aborts before the native import can fall back.\n  return false;'
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
          count = text.count("autoInstall: true")
          if count != 20:
              raise SystemExit(f"unexpected pi-lens auto-install policy count: {count}")
          policy.write_text(text.replace("autoInstall: true", "autoInstall: false"))

          replaced = 0
          for path in (root / "dist").rglob("*.js"):
              text = path.read_text()
              new = text.replace('"npx.cmd"', repr(denied_npx)).replace('"npx"', repr(denied_npx))
              if new != text:
                  replaced += 1
                  path.write_text(new)
          if replaced != 9:
              raise SystemExit(f"unexpected pi-lens npx file count: {replaced}")

          bundle = root / "dist/index.js"
          text = bundle.read_text()
          old = r'setStatus("pi-lens-lsp", parts.length > 0 ? parts.join(" \xB7 ") : theme.fg("dim", "LSP Inactive"));'
          new = 'setStatus("pi-lens-lsp", activeIds.length > 0 ? theme.bold("LSP") : theme.fg("dim", "LSP"));'
          if text.count(old) != 1:
              raise SystemExit("unexpected pi-lens status formatter")
          bundle.write_text(text.replace(old, new))
          PY
        ''}
      '';

  mkNpmPackageRoot =
    {
      pname,
      version,
      src,
      npmDepsHash,
      bundleEntry ? null,
      testBundleEntry ? null,
      prepareBundle ? (_root: ""),
    }:
    buildNpmPackage {
      inherit
        pname
        version
        src
        npmDepsHash
        ;
      nodejs = buildPackages.nodejs_22;
      npmInstallFlags = [
        "--ignore-scripts"
        "--omit=dev"
        "--omit=peer"
        "--legacy-peer-deps"
      ];
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

  hashlineSource = mkReleaseSource {
    name = "pi-hashline-edit-pro";
    tarball = releaseTarballs.pi-hashline-edit-pro;
    lockFile = ./locks/pi-hashline-edit-pro-package-lock.json;
    hashline = true;
  };
  smartFetchSource = mkReleaseSource {
    name = "pi-smart-fetch";
    tarball = releaseTarballs.pi-smart-fetch;
    lockFile = ./locks/pi-smart-fetch-package-lock.json;
    smartFetch = true;
  };
  smartWebSearchSource = mkReleaseSource {
    name = "pi-smart-web-search";
    tarball = releaseTarballs.pi-smart-web-search;
    lockFile = ./locks/pi-smart-web-search-package-lock.json;
  };
  lensSource = mkReleaseSource {
    name = "pi-lens";
    tarball = releaseTarballs.pi-lens;
    lockFile = ./locks/pi-lens-package-lock.json;
    lens = true;
  };
  markdownPreviewSource = mkReleaseSource {
    name = "pi-markdown-preview";
    tarball = releaseTarballs.pi-markdown-preview;
    lockFile = ./locks/pi-markdown-preview-package-lock.json;
  };
  betterwrightSource = mkReleaseSource {
    name = "betterwright";
    tarball = releaseTarballs.betterwright;
    lockFile = ./locks/betterwright-package-lock.json;
  };
  artifactsSource = mkReleaseSource {
    name = "pi-artifacts";
    tarball = releaseTarballs.pi-artifacts;
    lockFile = ./locks/pi-artifacts-package-lock.json;
  };
  insightsSource = mkReleaseSource {
    name = "pi-insights";
    tarball = releaseTarballs.pi-insights;
    lockFile = ./locks/pi-insights-package-lock.json;
  };
  dynamicWorkflowsSource = mkReleaseSource {
    name = "pi-dynamic-workflows";
    tarball = releaseTarballs.pi-dynamic-workflows;
    lockFile = ./locks/pi-dynamic-workflows-package-lock.json;
  };
  subagentsSource = mkReleaseSource {
    name = "pi-subagents";
    tarball = releaseTarballs.pi-subagents;
    lockFile = ./locks/pi-subagents-package-lock.json;
    subagents = true;
  };

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
  betterwright = mkNpmPackageRoot {
    pname = members.betterwright.attrName;
    version = members.betterwright.version;
    src = betterwrightSource;
    npmDepsHash = members.betterwright.hashes.npmDepsHash;
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
      old = """const MarkdownIt = require("markdown-it") as MarkdownItConstructor;
      // `lib/common` bundles the ~40 common grammars instead of all ~190.
      const hljsModule = require("highlight.js/lib/common") as
        | HighlightJsLike
        | { default: HighlightJsLike };
      const hljs = "default" in hljsModule ? hljsModule.default : hljsModule;
      const footnotePlugin = require("markdown-it-footnote") as (
        md: MarkdownItInstance,
      ) => void;"""
      new = """const MarkdownIt = MarkdownItImport as unknown as MarkdownItConstructor;
      // `lib/common` bundles the ~40 common grammars instead of all ~190.
      const hljsModule = hljsImport as unknown as
        | HighlightJsLike
        | { default: HighlightJsLike };
      const hljs = "default" in hljsModule ? hljsModule.default : hljsModule;
      const footnotePlugin = footnotePluginImport as unknown as (
        md: MarkdownItInstance,
      ) => void;"""
      if old not in text:
          raise SystemExit("pi-artifacts markdown require block drifted")
      markdown.write_text(text.replace(old, new))

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

  pi-retry = mkCopyRoot {
    pname = members.retry.attrName;
    version = members.retry.version;
    install = root: ''
      tar -xzf ${releaseTarballs.pi-retry} -C ${root} --strip-components=1
    '';
  };

  pi-provider-litellm = mkCopyRoot {
    pname = members.litellm.attrName;
    version = members.litellm.version;
    install = root: ''
      tar -xzf ${releaseTarballs.pi-provider-litellm} -C ${root} \
        --strip-components=1
      # Preserve the managed MCP and skill surfaces unless mutable Pi settings opt in.
      substituteInPlace ${root}/dist/index.js \
        --replace-fail \
          'const skillsEnabled = isFeatureEnabled(settings, "skills");' \
          'const skillsEnabled = settings?.skills?.enabled === true;' \
        --replace-fail \
          'const mcpEnabled = isFeatureEnabled(settings, "mcp");' \
          'const mcpEnabled = settings?.mcp?.enabled === true;' \
        --replace-fail \
          'sessionId = getSessionIdFromFile(ctx.sessionManager.getSessionFile());' \
          'sessionId = ctx.sessionManager.getSessionId() ?? getSessionIdFromFile(ctx.sessionManager.getSessionFile());'
      # The packaged Pi loader maps peer root exports, not these lazy subpaths.
      substituteInPlace ${root}/dist/provider.js \
        --replace-fail \
          $'import { createProvider } from "@earendil-works/pi-ai";\nimport { openAICompletionsApi } from "@earendil-works/pi-ai/api/openai-completions.lazy";\nimport { openAIResponsesApi } from "@earendil-works/pi-ai/api/openai-responses.lazy";' \
          'import { createProvider, openAICompletionsApi, openAIResponsesApi } from "@earendil-works/pi-ai";'
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

  pi-scroll = mkCopyRoot {
    pname = members.scroll.attrName;
    version = members.scroll.version;
    install = root: ''
      tar -xzf ${releaseTarballs.pi-scroll} -C ${root} --strip-components=1
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

  betterwrightBrowser =
    runCommand "betterwright-browser-${manifest.sourceCatalog.betterwright-chromium.version}"
      {
        nativeBuildInputs = [
          makeWrapper
          unzip
        ];
        passthru.version = manifest.sourceCatalog.betterwright-chromium.version;
        meta.mainProgram = "betterwright-chromium";
      }
      ''
        mkdir -p "$out/bin"
        unzip -q ${fetchurl manifest.sourceCatalog.betterwright-chromium.source.args} -d "$out"
        binary="$out/mac-arm64/Chromium.app/Contents/MacOS/Chromium"
        test -x "$binary"
        makeWrapper "$binary" "$out/bin/betterwright-chromium"
      '';

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
  ) order;
  galleryRegistrations = lib.concatMapStringsSep ",\n" (
    id: "            ${galleryIdentifier id}"
  ) order;

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
        }
        // lib.optionalAttrs stdenv.hostPlatform.isDarwin {
          inherit betterwrightBrowser;
        };
      }
      ''
        root="$out/share/pi-gallery"
        mkdir -p "$root"
        cat > "$root/index.ts" <<'TS'
        ${galleryImports}

        export default async function nixGallery(pi: unknown) {
          process.env.PONYTAIL_HIDE_STATUS = "1";
          process.env.PI_LENS_DISABLE_LSP_INSTALL = "1";
          process.env.PI_LENS_AUTO_INSTALL = "0";
          ${lib.optionalString stdenv.hostPlatform.isDarwin ''
            process.env.BETTERWRIGHT_CHROMIUM_PATH ??= ${builtins.toJSON "${betterwrightBrowser}/mac-arm64/Chromium.app/Contents/MacOS/Chromium"};
            process.env.PUPPETEER_EXECUTABLE_PATH ??= process.env.BETTERWRIGHT_CHROMIUM_PATH;
          ''}

          for (const extension of [
        ${galleryRegistrations}
          ]) {
            await extension(pi as never);
          }

          (pi as { on: (event: string, handler: () => unknown) => void }).on("resources_discover", () => ({
            skillPaths: ${builtins.toJSON (lib.concatMap (item: item.skills or [ ]) projection.packages)},
            promptPaths: ${builtins.toJSON (lib.concatMap (item: item.prompts or [ ]) projection.packages)},
          }));
        }
        TS
        cat > "$root/projection.json" <<'JSON'
        ${builtins.toJSON projection}
        JSON
      '';
in
assert
  inputs.agent-browser-source.rev == manifest.sourceCatalog.agent-browser-source.source.args.rev;
assert
  inputs.agent-browser-source.narHash
  == manifest.sourceCatalog.agent-browser-source.source.args.narHash;
assert inputs.pi-btw.rev == members.btw.artifacts.flakeInput.args.rev;
assert inputs.pi-btw.narHash == members.btw.artifacts.flakeInput.args.narHash;
assert inputs.ponytail.rev == members.ponytail.source.args.rev;
assert inputs.ponytail.narHash == members.ponytail.source.args.narHash;
assert
  builtins.hashFile "sha256" "${inputs.agent-browser-source}/cli/Cargo.toml"
  == "6880ec45ed03e83ab22bd21ac63c4dbaf6c8accd4da840dcf7536e5e48b1f98d";
galleryPackages // { inherit pi-gallery; }
