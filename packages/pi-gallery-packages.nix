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
  writeShellScript,
}:

let
  packageRoot = package: name: "${package}/share/pi-packages/${name}";

  releaseTarballs = {
    pi-hashline-edit-pro = fetchurl {
      url = "https://registry.npmjs.org/pi-hashline-edit-pro/-/pi-hashline-edit-pro-0.17.5.tgz";
      hash = "sha256-WrPRKhBNUJc6l4u1v4k8dftGUQA2Pj754zE07h3QTxU=";
    };
    pi-web-access = fetchurl {
      url = "https://registry.npmjs.org/pi-web-access/-/pi-web-access-0.13.0.tgz";
      hash = "sha256-GmPsueJdqj4Ny+fxlwMWRVnehe4bv1GeiBo0i5uAQAA=";
    };
    pi-lens = fetchurl {
      url = "https://registry.npmjs.org/pi-lens/-/pi-lens-3.8.71.tgz";
      hash = "sha256-YoBaBtZx5dz3QOtGharxOyVG/qlcmOTbAFVrlJ4fhqw=";
    };
    pi-dynamic-workflows = fetchurl {
      url = "https://registry.npmjs.org/@quintinshaw/pi-dynamic-workflows/-/pi-dynamic-workflows-3.4.1.tgz";
      hash = "sha256-5bCDyn+yzRr3rUxDzHT+bGbGxYrv8gSl7S3YhN+pZ0U=";
    };
    pi-agent-browser-native = fetchurl {
      url = "https://registry.npmjs.org/pi-agent-browser-native/-/pi-agent-browser-native-0.2.72.tgz";
      hash = "sha256-3subgZHSxRN4wigNrM0KO6o2QmNSr8PtdrT4mg2kRlE=";
    };
    pi-lean-ctx = fetchurl {
      url = "https://registry.npmjs.org/pi-lean-ctx/-/pi-lean-ctx-3.9.12.tgz";
      hash = "sha256-/DMfx45WnZU4/aFMBpg69T0WcNOtwxGcq/8habW6hpg=";
    };
    pi-btw = fetchurl {
      url = "https://registry.npmjs.org/pi-btw/-/pi-btw-0.4.1.tgz";
      hash = "sha256-CHzdNUd6Jo+ZMF0YvVoOw6piB+VQl4FHTKImwPwU/GI=";
    };
    pi-artifacts = fetchurl {
      url = "https://registry.npmjs.org/@jakeryderv/pi-artifacts/-/pi-artifacts-0.9.0.tgz";
      hash = "sha256-ONiw6EtStwrB6LESSyyKUOjGGWQDbFAvXlOsnKbcWaU=";
    };
    pi-insights = fetchurl {
      url = "https://registry.npmjs.org/@ygncode/pi-insights/-/pi-insights-1.0.1.tgz";
      hash = "sha256-vMNgilZxwQ5QOxcheTNrcPLQycmXYf5kvkLcLivwWEU=";
    };
    pi-subagentura = fetchurl {
      url = "https://registry.npmjs.org/pi-subagentura/-/pi-subagentura-3.0.3.tgz";
      hash = "sha256-8nSPMdy4LlJ1BIckjWdqFsSCcDo4uC5R9QqK6XJSVzU=";
    };
    pi-provider-litellm = fetchurl {
      url = "https://registry.npmjs.org/pi-provider-litellm/-/pi-provider-litellm-2.0.0.tgz";
      hash = "sha256-icmK1hCeZMU9ZINgg9fN0DZL8e/fS2Nbq6oJ4AKgVRU=";
    };
    pi-model-router = fetchurl {
      url = "https://registry.npmjs.org/@yeliu84/pi-model-router/-/pi-model-router-0.4.4.tgz";
      hash = "sha256-i5vZzLamyFEbyy+rZas4euSEneB8emIYPR6OoR7oasg=";
    };
    agent-browser = fetchurl {
      url = "https://registry.npmjs.org/agent-browser/-/agent-browser-0.33.0.tgz";
      hash = "sha256-Zdcyp6DFLuT1kCXvBX7ztk2GqqdiYrpk9IrBF4iJz4M=";
    };
  };

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
      webAccess ? false,
      dynamicWorkflows ? false,
      subagentura ? false,
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
        ' "$out/package.json" > "$out/package.json.normalized"
        mv "$out/package.json.normalized" "$out/package.json"
        cp ${lockFile} "$out/package-lock.json"

        ${lib.optionalString hashline ''
          substituteInPlace "$out/src/hash-store.ts" \
            --replace-fail \
              'async function tryLoadBetter(): Promise<boolean> {' \
              $'async function tryLoadBetter(): Promise<boolean> {\n  // Bun standalone aborts before the native import can fall back.\n  return false;'
        ''}

        ${lib.optionalString webAccess ''
          substituteInPlace "$out/index.ts" \
            --replace-fail 'loadConfig().provider' \
              '(process.env.PI_WEB_ACCESS_PROVIDER ?? loadConfig().provider)'
        ''}

        ${lib.optionalString dynamicWorkflows ''
          substituteInPlace "$out/extensions/workflow.ts" \
            --replace-fail \
              'excludeSubagentTools: settings.excludeSubagentTools,' \
              'excludeSubagentTools: ["subagent", ...(settings.excludeSubagentTools ?? [])],'
        ''}

        ${lib.optionalString subagentura ''
          substituteInPlace "$out/src/multiplexer.ts" \
            --replace-fail 'execFileSync("/bin/sh", ["-lc",' \
              'execFileSync("/bin/sh", ["-c",'
          substituteInPlace "$out/src/interactive-tmux.ts" \
            --replace-fail '"$ARTIFACT_DIR/cli.mjs" done 0' \
              'node "$ARTIFACT_DIR/cli.mjs" done 0' \
            --replace-fail '"$ARTIFACT_DIR/cli.mjs" error' \
              'node "$ARTIFACT_DIR/cli.mjs" error' \
            --replace-fail '`    "''${cliPath}" process-exit "$rc" || true`' \
              '`    node "''${cliPath}" process-exit "$rc" || true`' \
            --replace-fail '`"''${cliPath}" start`' \
              '`node "''${cliPath}" start`'
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
          cat > "$NIX_BUILD_TOP/pi-subagentura-pi-ai-shim.mjs" <<'EOF'
          export const getModel = () => undefined;
          export const getProviders = () => [];
          EOF
          cat > "$NIX_BUILD_TOP/pi-subagentura-coding-agent-shim.mjs" <<'EOF'
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
            --alias:@earendil-works/pi-ai/compat="$NIX_BUILD_TOP/pi-subagentura-pi-ai-shim.mjs" \
            --alias:@earendil-works/pi-coding-agent="$NIX_BUILD_TOP/pi-subagentura-coding-agent-shim.mjs" \
            --external:typebox \
            --outfile="$output"
        ''}
        runHook postInstall
      '';
    };

  hashlineSource = mkReleaseSource {
    name = "pi-hashline-edit-pro";
    tarball = releaseTarballs.pi-hashline-edit-pro;
    lockFile = ./pi-gallery-locks/pi-hashline-edit-pro-package-lock.json;
    hashline = true;
  };
  webAccessSource = mkReleaseSource {
    name = "pi-web-access";
    tarball = releaseTarballs.pi-web-access;
    lockFile = ./pi-gallery-locks/pi-web-access-package-lock.json;
    dropPeerMetadata = false;
    webAccess = true;
  };
  lensSource = mkReleaseSource {
    name = "pi-lens";
    tarball = releaseTarballs.pi-lens;
    lockFile = ./pi-gallery-locks/pi-lens-package-lock.json;
    lens = true;
  };
  dynamicWorkflowsSource = mkReleaseSource {
    name = "pi-dynamic-workflows";
    tarball = releaseTarballs.pi-dynamic-workflows;
    lockFile = ./pi-gallery-locks/pi-dynamic-workflows-package-lock.json;
    dynamicWorkflows = true;
  };
  artifactsSource = mkReleaseSource {
    name = "pi-artifacts";
    tarball = releaseTarballs.pi-artifacts;
    lockFile = ./pi-gallery-locks/pi-artifacts-package-lock.json;
  };
  insightsSource = mkReleaseSource {
    name = "pi-insights";
    tarball = releaseTarballs.pi-insights;
    lockFile = ./pi-gallery-locks/pi-insights-package-lock.json;
  };
  subagenturaSource = mkReleaseSource {
    name = "pi-subagentura";
    tarball = releaseTarballs.pi-subagentura;
    lockFile = ./pi-gallery-locks/pi-subagentura-package-lock.json;
    subagentura = true;
  };

  pi-hashline-edit-pro = mkNpmPackageRoot {
    pname = "pi-hashline-edit-pro";
    version = "0.17.5";
    src = hashlineSource;
    npmDepsHash = "sha256-sk7mvBP3/SwAFt3GYN1OL2SwNk1s5nC47UUsT1cxB2Y=";
  };
  pi-web-access = mkNpmPackageRoot {
    pname = "pi-web-access";
    version = "0.13.0";
    src = webAccessSource;
    npmDepsHash = "sha256-8onTvv7nUrTXMGvwkMkPEYc+mtpxolzF6Z9EuuB9pbs=";
  };
  pi-lens = mkNpmPackageRoot {
    pname = "pi-lens";
    version = "3.8.71";
    src = lensSource;
    npmDepsHash = "sha256-QZClnuBwVYZ+h5lb4YqsJ6VzgWyQQdnTMa05UdzcB78=";
  };
  pi-dynamic-workflows = mkNpmPackageRoot {
    pname = "pi-dynamic-workflows";
    version = "3.4.1";
    src = dynamicWorkflowsSource;
    npmDepsHash = "sha256-49v98jLmhF0K40OoVimaGy8DXpDrsWuhGsKuPbqsm1U=";
  };
  pi-artifacts = mkNpmPackageRoot {
    pname = "pi-artifacts";
    version = "0.9.0";
    src = artifactsSource;
    npmDepsHash = "sha256-uEXAE4Hy6mAFWsb8kckPMlksGgGB93pekjs5mqwlAGk=";
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
    pname = "pi-insights";
    version = "1.0.1";
    src = insightsSource;
    npmDepsHash = "sha256-JaRVe4RXIsXHBIppE0dCJwsgBG3c2+N+8pM68pKkoFI=";
  };
  pi-subagentura = mkNpmPackageRoot {
    pname = "pi-subagentura";
    version = "3.0.3";
    src = subagenturaSource;
    npmDepsHash = "sha256-wx7BImm7rrpzamuZp9s5UD5kv0ENmAwTnknkR3Ja2jU=";
    bundleEntry = "src/subagent.ts";
    testBundleEntry = "src/multiplexer-tmux.ts";
  };

  subagenturaTestSource = runCommand "pi-subagentura-test-source" { nativeBuildInputs = [ jq ]; } ''
    cp -R -- ${inputs.pi-subagentura}/. "$out"/
    chmod -R u+w "$out"
    ${jq}/bin/jq '.devDependencies.typebox = "1.1.37"' \
      "$out/package.json" > "$out/package.json.tmp"
    mv "$out/package.json.tmp" "$out/package.json"
    ${jq}/bin/jq '.packages[""].devDependencies.typebox = "1.1.37"' \
      "$out/package-lock.json" > "$out/package-lock.json.tmp"
    mv "$out/package-lock.json.tmp" "$out/package-lock.json"
    substituteInPlace "$out/src/multiplexer.ts" \
      --replace-fail 'execFileSync("/bin/sh", ["-lc",' \
        'execFileSync("/bin/sh", ["-c",'
    substituteInPlace "$out/src/interactive-tmux.ts" \
      --replace-fail '"$ARTIFACT_DIR/cli.mjs" done 0' \
        'node "$ARTIFACT_DIR/cli.mjs" done 0' \
      --replace-fail '"$ARTIFACT_DIR/cli.mjs" error' \
        'node "$ARTIFACT_DIR/cli.mjs" error' \
      --replace-fail '`    "''${cliPath}" process-exit "$rc" || true`' \
        '`    node "''${cliPath}" process-exit "$rc" || true`' \
      --replace-fail '`"''${cliPath}" start`' \
        '`node "''${cliPath}" start`'
    substituteInPlace "$out/tests/subagent-launch-script.test.ts" \
      --replace-fail '`"''${join(artDir, "cli.mjs")}"' \
        '`node "''${join(artDir, "cli.mjs")}"'
    substituteInPlace \
      "$out/tests/multiplexer-tmux.test.ts" \
      "$out/tests/multiplexer-zellij.test.ts" \
      --replace-fail 'args.includes("-lc")' 'args[0] === "-c"'
  '';

  subagenturaTests = buildNpmPackage {
    pname = "pi-subagentura-tests";
    version = "3.0.3";
    src = subagenturaTestSource;
    nodejs = buildPackages.nodejs_22;
    npmDepsHash = "sha256-3VesSLfU89SNnv7LJ19bikkViL4++O1Rd7yTxOjBVuA=";
    npmDepsFetcherVersion = 2;
    npmInstallFlags = [
      "--ignore-scripts"
      "--legacy-peer-deps"
    ];
    dontNpmBuild = true;
    doCheck = true;
    checkPhase = ''
      runHook preCheck
      npm run test:unit
      runHook postCheck
    '';
    installPhase = ''
      touch "$out"
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

  bigpowers = mkCopyRoot {
    pname = "bigpowers";
    version = "2.84.0";
    install = root: ''
      cp -R -- ${inputs.bigpowers}/.pi ${root}/
      cp -- ${inputs.bigpowers}/package.json ${inputs.bigpowers}/LICENSE \
        ${inputs.bigpowers}/README.md ${root}/
    '';
  };

  pi-btw = mkCopyRoot {
    pname = "pi-btw";
    version = "0.4.1";
    install = root: ''
      tar -xzf ${releaseTarballs.pi-btw} -C ${root} --strip-components=1
      mkdir -p ${root}/skills/btw
      cp -- ${inputs.pi-btw}/skills/btw/SKILL.md ${root}/skills/btw/SKILL.md
      cmp ${inputs.pi-btw}/extensions/btw.ts ${root}/extensions/btw.ts
    '';
  };

  pi-ponytail = mkCopyRoot {
    pname = "pi-ponytail";
    version = "4.8.4";
    install = root: ''
      cp -R -- ${inputs.ponytail}/pi-extension ${inputs.ponytail}/hooks \
        ${inputs.ponytail}/skills ${root}/
      cp -- ${inputs.ponytail}/package.json ${inputs.ponytail}/LICENSE \
        ${inputs.ponytail}/README.md ${root}/
    '';
  };

  pi-agent-browser-native = mkCopyRoot {
    pname = "pi-agent-browser-native";
    version = "0.2.72";
    install = root: ''
      tar -xzf ${releaseTarballs.pi-agent-browser-native} -C ${root} \
        --strip-components=1
    '';
  };

  pi-lean-ctx = mkCopyRoot {
    pname = "pi-lean-ctx";
    version = "3.9.12";
    install = root: ''
      tar -xzf ${releaseTarballs.pi-lean-ctx} -C ${root} \
        --strip-components=1
      cp -- ${inputs.lean-ctx}/LICENSE ${root}/LICENSE
    '';
  };

  pi-provider-litellm = mkCopyRoot {
    pname = "pi-provider-litellm";
    version = "2.0.0";
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
          'const mcpEnabled = settings?.mcp?.enabled === true;'
      # The packaged Pi loader maps peer root exports, not these lazy subpaths.
      substituteInPlace ${root}/dist/provider.js \
        --replace-fail \
          $'import { createProvider } from "@earendil-works/pi-ai";\nimport { openAICompletionsApi } from "@earendil-works/pi-ai/api/openai-completions.lazy";\nimport { openAIResponsesApi } from "@earendil-works/pi-ai/api/openai-responses.lazy";' \
          'import { createProvider, openAICompletionsApi, openAIResponsesApi } from "@earendil-works/pi-ai";'
    '';
  };

  pi-model-router = mkCopyRoot {
    pname = "pi-model-router";
    version = "0.4.4";
    install = root: ''
      tar -xzf ${releaseTarballs.pi-model-router} -C ${root} \
        --strip-components=1
    '';
  };

  lean-ctx = inputs.llm-agents.packages.${stdenv.hostPlatform.system}.lean-ctx;

  agent-browser =
    runCommand "agent-browser-0.33.0"
      {
        nativeBuildInputs = [
          findutils
          makeWrapper
        ]
        ++ lib.optional stdenv.hostPlatform.isLinux patchelf;
        passthru.version = "0.33.0";
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

  roots = {
    btw = packageRoot pi-btw "pi-btw";
    artifacts = packageRoot pi-artifacts "pi-artifacts";
    insights = packageRoot pi-insights "pi-insights";
    subagentura = packageRoot pi-subagentura "pi-subagentura";
    litellm = packageRoot pi-provider-litellm "pi-provider-litellm";
    router = packageRoot pi-model-router "pi-model-router";
    hashline = packageRoot pi-hashline-edit-pro "pi-hashline-edit-pro";
    web = packageRoot pi-web-access "pi-web-access";
    lens = packageRoot pi-lens "pi-lens";
    ponytail = packageRoot pi-ponytail "pi-ponytail";
    workflows = packageRoot pi-dynamic-workflows "pi-dynamic-workflows";
    browser = packageRoot pi-agent-browser-native "pi-agent-browser-native";
    lean = packageRoot pi-lean-ctx "pi-lean-ctx";
  };

  projection = {
    packages = [
      {
        name = "pi-hashline-edit-pro";
        version = "0.17.5";
        extensions = [ "${roots.hashline}/index.ts" ];
      }
      {
        name = "pi-web-access";
        version = "0.13.0";
        extensions = [ "${roots.web}/index.ts" ];
        skills = [ "${roots.web}/skills" ];
      }
      {
        name = "pi-lens";
        version = "3.8.71";
        extensions = [ "${roots.lens}/dist/index.js" ];
        skills = [ "${roots.lens}/skills" ];
      }
      {
        name = "@dietrichgebert/ponytail";
        version = "4.8.4+${builtins.substring 0 7 inputs.ponytail.rev}";
        extensions = [ "${roots.ponytail}/pi-extension/index.js" ];
        skills = [ ];
      }
      {
        name = "@quintinshaw/pi-dynamic-workflows";
        version = "3.4.1";
        extensions = [ "${roots.workflows}/extensions/workflow.ts" ];
        skills = [
          "${roots.workflows}/skills/workflow-authoring"
          "${roots.workflows}/skills/workflow-patterns"
        ];
      }
      {
        name = "pi-agent-browser-native";
        version = "0.2.72";
        extensions = [ "${roots.browser}/dist/extensions/agent-browser/index.js" ];
      }
      {
        name = "pi-lean-ctx";
        version = "3.9.12";
        extensions = [ "${roots.lean}/extensions/index.ts" ];
      }
      {
        name = "pi-btw";
        version = "0.4.1";
        extensions = [ "${roots.btw}/extensions/btw.ts" ];
        skills = [ "${roots.btw}/skills/btw" ];
      }
      {
        name = "@jakeryderv/pi-artifacts";
        version = "0.9.0";
        extensions = [ "${roots.artifacts}/extensions/nix-bundle.js" ];
        skills = [ "${roots.artifacts}/skills/artifacts-authoring" ];
      }
      {
        name = "@ygncode/pi-insights";
        version = "1.0.1";
        extensions = [ "${roots.insights}/index.ts" ];
      }
      {
        name = "pi-subagentura";
        version = "3.0.3";
        extensions = [ "${roots.subagentura}/src/nix-bundle.js" ];
        skills = [ "${roots.subagentura}/skills/ralplan" ];
      }
      {
        name = "pi-provider-litellm";
        version = "2.0.0";
        extensions = [ "${roots.litellm}/dist/index.js" ];
      }
      {
        name = "@yeliu84/pi-model-router";
        version = "0.4.4";
        extensions = [ "${roots.router}/extensions/index.ts" ];
      }
    ];
  };

  pi-gallery =
    runCommand "pi-gallery"
      {
        passthru = {
          inherit projection roots subagenturaTests;
          packages = {
            inherit
              agent-browser
              bigpowers
              lean-ctx
              pi-agent-browser-native
              pi-artifacts
              pi-btw
              pi-dynamic-workflows
              pi-hashline-edit-pro
              pi-insights
              pi-lean-ctx
              pi-lens
              pi-ponytail
              pi-subagentura
              pi-provider-litellm
              pi-model-router
              pi-web-access
              ;
          };
        };
      }
      ''
        root="$out/share/pi-gallery"
        mkdir -p "$root"
        cat > "$root/index.ts" <<'TS'
        import hashline from ${builtins.toJSON "${roots.hashline}/index.ts"};
        import webAccess from ${builtins.toJSON "${roots.web}/index.ts"};
        import lens from ${builtins.toJSON "${roots.lens}/dist/index.js"};
        import ponytail from ${builtins.toJSON "${roots.ponytail}/pi-extension/index.js"};
        import workflows from ${builtins.toJSON "${roots.workflows}/extensions/workflow.ts"};
        import browser from ${builtins.toJSON "${roots.browser}/dist/extensions/agent-browser/index.js"};
        import leanCtx from ${builtins.toJSON "${roots.lean}/extensions/index.ts"};
        import btw from ${builtins.toJSON "${roots.btw}/extensions/btw.ts"};
        import artifacts from ${builtins.toJSON "${roots.artifacts}/extensions/nix-bundle.js"};
        import insights from ${builtins.toJSON "${roots.insights}/index.ts"};
        import subagentura from ${builtins.toJSON "${roots.subagentura}/src/nix-bundle.js"};
        import litellm from ${builtins.toJSON "${roots.litellm}/dist/index.js"};
        import router from ${builtins.toJSON "${roots.router}/extensions/index.ts"};

        export default async function nixGallery(pi: unknown) {
          process.env.PI_WEB_ACCESS_PROVIDER = "perplexity";
          process.env.PI_LENS_DISABLE_LSP_INSTALL = "1";
          process.env.PI_LENS_AUTO_INSTALL = "0";
          process.env.LEAN_CTX_BIN = ${builtins.toJSON "${lean-ctx}/bin/lean-ctx"};

          for (const extension of [
            hashline,
            webAccess,
            lens,
            ponytail,
            workflows,
            browser,
            leanCtx,
            btw,
            artifacts,
            insights,
            subagentura,
            litellm,
            router,
          ]) {
            await extension(pi as never);
          }

          (pi as { on: (event: string, handler: () => unknown) => void }).on("resources_discover", () => ({
            skillPaths: ${builtins.toJSON (lib.concatMap (item: item.skills or [ ]) projection.packages)},
          }));
        }
        TS
        cat > "$root/projection.json" <<'JSON'
        ${builtins.toJSON projection}
        JSON
      '';
in
assert inputs.agent-browser-source.rev == "1ed371f3af472cc0d6cd8fdaea75d1a085ff7534";
assert inputs.agent-browser-source.narHash == "sha256-praWvAgWoDmWqXzh/kxdfQAPGkVS4qkb0pPYtMWO/N8=";
assert
  builtins.hashFile "sha256" "${inputs.agent-browser-source}/cli/Cargo.toml"
  == "6880ec45ed03e83ab22bd21ac63c4dbaf6c8accd4da840dcf7536e5e48b1f98d";
{
  inherit
    agent-browser
    bigpowers
    lean-ctx
    pi-agent-browser-native
    pi-artifacts
    pi-btw
    pi-dynamic-workflows
    pi-gallery
    pi-hashline-edit-pro
    pi-insights
    pi-lean-ctx
    pi-lens
    pi-ponytail
    pi-subagentura
    pi-provider-litellm
    pi-model-router
    pi-web-access
    ;
}
