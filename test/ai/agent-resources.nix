{
  pkgs,
  ponytail ? null,
  translate-tool ? null,
  gitSurgeonSource ? null,
  sourceOnlyResources ? null,
  piMcpAdapter ? null,
  piOpenaiServerCompaction ? null,
  piQuiet ? null,
  piPackage,
}:

let
  inherit (pkgs) lib;
  piSources = import ../../packages/source-catalog.nix "pi";
  skillCreatorSource = ../../config/ai/skills/skill-creator;
  skillCreatorPython = pkgs.python3.withPackages (pythonPackages: [ pythonPackages.pyyaml ]);
  skillCreatorScripts = [
    "init_skill.py"
    "package_skill.py"
    "quick_validate.py"
  ];

  ponytailSkills = [
    "ponytail"
    "ponytail-review"
    "ponytail-audit"
    "ponytail-debt"
    "ponytail-gain"
    "ponytail-help"
  ];

  expectedSkills = ponytailSkills ++ [
    "git-surgeon"
    "skill-creator"
    "translate-en"
  ];

  resources = pkgs.agent-resources;
  haveSources = ponytail != null && translate-tool != null && gitSurgeonSource != null;
  havePiSources = piMcpAdapter != null && piOpenaiServerCompaction != null && piQuiet != null;
  catalog = import ../../config/ai/catalog.nix {
    inherit lib resources;
  };
  piProfile = catalog.profiles.hera-pi;
  mcpEnvironmentProbeScript = pkgs.writeText "mcp-environment-probe.py" (
    builtins.readFile ./mcp-environment-probe.py
  );
  piMcpRegistryItems = catalog.items // {
    mcpServers = {
      managed-environment-probe = {
        selectors.clients = [ "pi" ];
        transport = {
          command = "${pkgs.python3}/bin/python3";
          args = [
            { public = toString mcpEnvironmentProbeScript; }
            { public = pkgs.nix-managed-mcp-stdio.runtimePath; }
          ];
          env = {
            ANTHROPIC_API_KEY.env = "ANTHROPIC_API_KEY";
            DEFAULT_MODEL = "auto";
            OPENAI_API_KEY.env = "OPENAI_API_KEY";
          };
        };
      };
    };
  };
  piMcpRegistry = (import ../../config/ai/renderers/mcp-registry.nix { inherit lib pkgs; }) {
    projection = catalog.sharedMcpRegistryFor {
      profiles = [ piProfile ];
      items = piMcpRegistryItems;
    };
    homeDirectory = "/Users/test";
    xdgConfigHome = "/Users/test/.config";
  };
  piMcpRegistryFile = piMcpRegistry.files.".config/mcp/mcp.json".source;
  piMcpSyntheticProvider = pkgs.writeText "pi-mcp-synthetic-provider.ts" ''
    import { registerFauxProvider } from "@earendil-works/pi-ai/compat";

    const zeroUsage = {
      input: 0,
      output: 0,
      cacheRead: 0,
      cacheWrite: 0,
      totalTokens: 0,
      cost: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0, total: 0 },
    };
    const assistantMessage = (content: any, stopReason = "stop") => ({
      role: "assistant",
      content: typeof content === "string" ? [{ type: "text", text: content }] : [content],
      api: "faux",
      provider: "faux",
      model: "faux-1",
      usage: zeroUsage,
      stopReason,
      timestamp: Date.now(),
    });

    export default function syntheticMcpProvider(pi: any) {
      const faux = registerFauxProvider({
        api: "synthetic-mcp-api",
        provider: "synthetic-mcp",
        models: [{ id: "target", name: "Synthetic MCP" }],
      });
      faux.setResponses([
        assistantMessage(
          {
            type: "toolCall",
            id: "tool:managed-mcp",
            name: "mcp",
            arguments: {
              tool: "managed-environment-probe_environment_ok",
              server: "managed-environment-probe",
              args: { value: "round-trip" },
            },
          },
          "toolUse",
        ),
        (context: any) => {
          const result = context.messages.findLast(
            (message: any) => message.role === "toolResult" && message.toolName === "mcp",
          );
          const text = result?.content
            ?.filter((item: any) => item.type === "text")
            .map((item: any) => item.text)
            .join("\n");
          return assistantMessage(
            text?.includes("synthetic-mcp:round-trip")
              ? "pi-mcp-round-trip-ok"
              : "pi-mcp-round-trip-failed",
          );
        },
      ]);
      pi.registerProvider("synthetic-mcp", {
        baseUrl: "synthetic://local",
        apiKey: "synthetic",
        api: faux.api,
        models: faux.models,
      });
    }
  '';

  piQuietFiles = [
    "package.json"
    "CHANGELOG.md"
    "README.md"
    "src/bash-settings.ts"
    "src/classify.ts"
    "src/command.ts"
    "src/compaction.ts"
    "src/config.ts"
    "src/format.ts"
    "src/history.ts"
    "src/index.ts"
    "src/result-content.ts"
    "src/shell.ts"
    "src/tool-renderer-api.ts"
    "src/tools-meta.ts"
    "src/tools.ts"
  ];

  piOpenaiServerCompactionFiles = [
    "package.json"
    "LICENSE.md"
    "README.md"
    "src/config.ts"
    "src/custom-stream.ts"
    "src/index.ts"
    "src/openai-ws-connection.ts"
    "src/openai-ws-stream.ts"
    "src/openai.ts"
    "src/remote-compaction.ts"
    "src/state.ts"
    "src/stream-message-shared.ts"
  ];

  wsSource = pkgs.fetchzip piSources.ws.source.args;
  wsTypes = pkgs.fetchzip {
    url = "https://registry.npmjs.org/@types/ws/-/ws-8.18.1.tgz";
    hash = "sha256-b3zpflsUAU9KpAT1uQb4QLZMbPn7faYlDdm8vNRWNzY=";
  };

  piMcpFiles = [
    "cli.js"
    "agent-dir.ts"
    "agent-plugin-loader.ts"
    "index.ts"
    "error-signal.ts"
    "state.ts"
    "utils.ts"
    "abort.ts"
    "runtime-owner.ts"
    "tool-metadata.ts"
    "init.ts"
    "failure-backoff.ts"
    "ui-session.ts"
    "proxy-modes.ts"
    "direct-tools.ts"
    "namespace-tools.ts"
    "mcp-references.ts"
    "commands.ts"
    "prompts.ts"
    "onboarding-state.ts"
    "mcp-setup-panel.ts"
    "mcp-code.ts"
    "mcp-bearer-store.ts"
    "mcp-keyring-helper.cjs"
    "mcp-probe.ts"
    "mcp-script-worker.mjs"
    "types.ts"
    "ui-stream-types.ts"
    "config.ts"
    "package-mcp-loader.ts"
    "server-manager.ts"
    "unix-socket-transport.ts"
    "json-schema-validator.ts"
    "session-recovery.ts"
    "sampling-handler.ts"
    "elicitation-handler.ts"
    "tool-registrar.ts"
    "tool-result-renderer.ts"
    "mcp-output-guard.ts"
    "resource-tools.ts"
    "lifecycle.ts"
    "mcp-status.ts"
    "metadata-cache.ts"
    "host-html-template.ts"
    "ui-resource-handler.ts"
    "consent-manager.ts"
    "ui-server.ts"
    "glimpse-ui.ts"
    "npx-resolver.ts"
    "oauth.ts"
    "oauth-handler.ts"
    "mcp-auth.ts"
    "mcp-oauth-provider.ts"
    "mcp-callback-server.ts"
    "mcp-auth-flow.ts"
    "mcp-panel.ts"
    "panel-keys.ts"
    "mcp-trace.ts"
    "request-headers-command.ts"
    "search-ranking.ts"
    "logger.ts"
    "tool-approval.ts"
    "ts-shape.ts"
    "ui-app-bridge-helpers.ts"
    "ui-tool-visibility.ts"
    "errors.ts"
    "app-bridge.bundle.js"
    "banner.png"
    "README.md"
    "CHANGELOG.md"
    "LICENSE"
  ];

  piMcpPublicSources = [
    "agent-dir.ts"
    "agent-plugin-loader.ts"
    "config.ts"
    "mcp-bearer-store.ts"
    "metadata-cache.ts"
    "package-mcp-loader.ts"
    "resource-tools.ts"
    "types.ts"
    "ui-app-bridge-helpers.ts"
    "ui-stream-types.ts"
    "ui-tool-visibility.ts"
    "utils.ts"
  ];
  piMcpPublicDistFiles = lib.concatMap (
    source:
    let
      stem = lib.removeSuffix ".ts" source;
    in
    [
      "${stem}.d.ts"
      "${stem}.js"
      "${stem}.js.map"
    ]
  ) piMcpPublicSources;

  piMcpFileArgs = lib.escapeShellArgs ([ "package.json" ] ++ piMcpFiles);
  piMcpPublicDistFileArgs = lib.escapeShellArgs piMcpPublicDistFiles;
  piMcpTopLevelArgs = lib.escapeShellArgs (
    [ "package.json" ]
    ++ piMcpFiles
    ++ [
      "node_modules"
      "skills"
      "dist"
    ]
  );
  piQuietFileArgs = lib.escapeShellArgs piQuietFiles;
  piQuietPackagedFileArgs = lib.escapeShellArgs (piQuietFiles ++ [ "LICENSE" ]);
  piOpenaiServerCompactionFileArgs = lib.escapeShellArgs piOpenaiServerCompactionFiles;

  expectedSkillArgs = lib.escapeShellArgs expectedSkills;
  ponytailSkillArgs = lib.escapeShellArgs ponytailSkills;
  skillCreatorScriptArgs = lib.escapeShellArgs skillCreatorScripts;

  copyPonytailExpected = lib.concatMapStringsSep "\n" (name: ''
    copy_expected_tree ${lib.escapeShellArg "${ponytail}/skills/${name}"} "$expected/${name}"
    chmod --reference=${lib.escapeShellArg "${ponytail}/skills/${name}"} "$expected/${name}"
  '') ponytailSkills;

  piClosureCheck = pkgs.writeText "check-pi-extension-closure.mjs" ''
    import fs from "node:fs";
    import path from "node:path";
    import { pathToFileURL } from "node:url";

    const [mcpRoot, lockFile] = process.argv.slice(2);

    function fail(message) {
      console.error("Pi extension closure check: " + message);
      process.exit(1);
    }

    const lock = JSON.parse(fs.readFileSync(lockFile, "utf8"));
    if (lock.lockfileVersion !== 3) fail("unexpected pi-mcp-adapter lockfile version");

    const locked = new Map(Object.entries(lock.packages).filter(([name]) => name !== ""));
    const actual = new Set();

    function visitNodeModules(nodeModules, prefix) {
      if (!fs.existsSync(nodeModules)) return;
      for (const entry of fs.readdirSync(nodeModules, { withFileTypes: true })) {
        if (entry.name === ".bin" || entry.name.startsWith(".")) continue;
        if (entry.name.startsWith("@")) {
          const scope = path.join(nodeModules, entry.name);
          for (const child of fs.readdirSync(scope, { withFileTypes: true })) {
            if (!child.isDirectory()) continue;
            visitPackage(path.join(scope, child.name), prefix + "node_modules/" + entry.name + "/" + child.name);
          }
        } else if (entry.isDirectory()) {
          visitPackage(path.join(nodeModules, entry.name), prefix + "node_modules/" + entry.name);
        }
      }
    }

    function visitPackage(root, key) {
      if (!fs.existsSync(path.join(root, "package.json"))) return;
      actual.add(key);
      visitNodeModules(path.join(root, "node_modules"), key + "/");
    }

    visitNodeModules(path.join(mcpRoot, "node_modules"), "");

    for (const name of actual) {
      const metadata = locked.get(name);
      if (!metadata) fail("installed package is absent from package-lock.json: " + name);
      if (metadata.dev === true) fail("development package leaked into closure: " + name);
      if (!metadata.integrity) fail("installed package lacks locked integrity: " + name);
    }

    for (const [name, metadata] of locked) {
      if (metadata.dev !== true && metadata.optional !== true && !actual.has(name)) {
        fail("required locked package is absent from closure: " + name);
      }
    }

    const expectedDirect = Object.keys(lock.packages[""]?.dependencies ?? {});
    for (const name of expectedDirect) {
      const key = "node_modules/" + name;
      if (!actual.has(key)) fail("missing direct runtime dependency: " + name);
    }
    for (const peer of ["@earendil-works/pi-ai", "@earendil-works/pi-tui", "typebox"]) {
      if (actual.has("node_modules/" + peer)) {
        fail("Pi-provided peer leaked into closure: " + peer);
      }
    }

    const runtimeImports = [
      "@modelcontextprotocol/ext-apps/app-bridge",
      "@modelcontextprotocol/sdk/client/auth.js",
      "@modelcontextprotocol/sdk/client/index.js",
      "@modelcontextprotocol/sdk/client/sse.js",
      "@modelcontextprotocol/sdk/client/stdio.js",
      "@modelcontextprotocol/sdk/client/streamableHttp.js",
      "@modelcontextprotocol/sdk/types.js",
      "@modelcontextprotocol/sdk/validation/ajv",
      "open",
      "recheck",
      "zod"
    ];
    const parent = pathToFileURL(path.join(mcpRoot, "index.ts")).href;
    const closure = fs.realpathSync(path.join(mcpRoot, "node_modules"));
    for (const specifier of runtimeImports) {
      let resolved;
      try {
        resolved = import.meta.resolve(specifier, parent);
      } catch (error) {
        fail("cannot resolve runtime import " + specifier + ": " + error.message);
      }
      if (!resolved.startsWith("file:")) fail("non-file runtime import: " + specifier);
      const real = fs.realpathSync(new URL(resolved));
      if (real !== closure && !real.startsWith(closure + path.sep)) {
        fail("runtime import escapes packaged closure: " + specifier + " -> " + real);
      }
    }
  '';
in
assert resources != null;
assert sourceOnlyResources != null;
if !haveSources then
  throw "agent-resources check requires all pinned source roots"
else
  pkgs.runCommand "agent-resources-check"
    {
      nativeBuildInputs = [
        pkgs.coreutils
        pkgs.findutils
        pkgs.gnugrep
        pkgs.jq
        pkgs.nodejs
        pkgs.typescript
      ];
    }
    ''
      set -euo pipefail

      actual=${resources}/share/agent-resources/skills
      expected="$TMPDIR/expected"
      mkdir -p "$expected"

      fail() {
        printf 'agent-resources check: %s\n' "$*" >&2
        exit 1
      }

      test ${sourceOnlyResources} = ${resources} \
        || fail "source-only agent-resources derivation differs"

      copy_expected_tree() {
        source_tree=$1
        destination=$2

        [ -d "$source_tree" ] && [ ! -L "$source_tree" ] \
          || fail "invalid source skill tree: $source_tree"
        [ ! -e "$destination" ] && [ ! -L "$destination" ] \
          || fail "duplicate expected skill destination: $destination"
        mkdir "$destination"
        cp -a -- "$source_tree"/. "$destination"/
        chmod u+w "$destination"
      }

      validate_tree() {
        tree=$1
        [ -d "$tree" ] && [ ! -L "$tree" ] || fail "invalid tree root: $tree"
        canonical_tree=$(realpath -e -- "$tree")

        while IFS= read -r -d "" path; do
          if [ -L "$path" ]; then
            target=$(readlink -- "$path")
            [ -n "$target" ] || fail "empty symlink target: $path"
            case "$target" in
              /*) fail "absolute symlink: $path -> $target" ;;
            esac
            [ -e "$path" ] || fail "dangling symlink: $path -> $target"
            resolved=$(realpath -e -- "$path")
            case "$resolved" in
              "$canonical_tree" | "$canonical_tree"/*) ;;
              *) fail "escaping symlink: $path -> $target" ;;
            esac
          elif [ ! -d "$path" ] && [ ! -f "$path" ]; then
            fail "special file in skill tree: $path"
          fi
        done < <(find -P "$tree" -mindepth 1 -print0)
      }

      write_manifest() {
        tree=$1
        output=$2
        : >"$output"
        validate_tree "$tree"

        while IFS= read -r -d "" path; do
          relative=''${path#"$tree"/}
          mode=$(stat -c '%a' -- "$path")
          target=
          digest=

          if [ -L "$path" ]; then
            type=l
            target=$(readlink -- "$path")
          elif [ -d "$path" ]; then
            type=d
          elif [ -f "$path" ]; then
            type=f
            digest=$(sha256sum -- "$path")
            digest=''${digest%% *}
          else
            fail "unsupported file type: $path"
          fi

          printf '%s\0%s\0%s\0%s\0%s\0' \
            "$relative" "$type" "$mode" "$target" "$digest" >>"$output"
        done < <(find -P "$tree" -mindepth 1 -print0 | sort -z)
      }

      ${copyPonytailExpected}
      copy_expected_tree ${lib.escapeShellArg "${skillCreatorSource}"} \
        "$expected/skill-creator"
      for script in ${skillCreatorScriptArgs}; do
        substituteInPlace "$expected/skill-creator/scripts/$script" \
          --replace-fail '#!/usr/bin/env python3' \
          '#!${skillCreatorPython}/bin/python3'
        chmod --reference=${lib.escapeShellArg "${skillCreatorSource}/scripts"}/"$script" \
          "$expected/skill-creator/scripts/$script"
      done
      chmod --reference=${lib.escapeShellArg "${skillCreatorSource}"} \
        "$expected/skill-creator"
      copy_expected_tree \
        ${lib.escapeShellArg "${gitSurgeonSource}/skills/git-surgeon"} \
        "$expected/git-surgeon"
      cp -a -- ${lib.escapeShellArg "${gitSurgeonSource}/LICENSE"} \
        "$expected/git-surgeon/LICENSE"
      chmod --reference=${lib.escapeShellArg "${gitSurgeonSource}/skills/git-surgeon"} \
        "$expected/git-surgeon"
      copy_expected_tree ${lib.escapeShellArg "${translate-tool}/skill"} \
        "$expected/translate-en"
      rm -- "$expected/translate-en/GLOSSARY.csv"
      cp -a -- ${lib.escapeShellArg "${translate-tool}/glossary.csv"} \
        "$expected/translate-en/GLOSSARY.csv"
      chmod --reference=${lib.escapeShellArg "${translate-tool}/skill"} \
        "$expected/translate-en"

      [ -d "$actual" ] && [ ! -L "$actual" ] \
        || fail "missing regular skills root: $actual"

      printf '%s\0' ${expectedSkillArgs} | sort -z >"$TMPDIR/expected-names"
      if [ "$(tr '\0' '\n' <"$TMPDIR/expected-names" | uniq -d | wc -l)" -ne 0 ]; then
        fail "duplicate name in the independent expected skill list"
      fi
      find -P "$actual" -mindepth 1 -maxdepth 1 -printf '%f\0' \
        | sort -z >"$TMPDIR/actual-names"
      cmp "$TMPDIR/expected-names" "$TMPDIR/actual-names" \
        || fail "skill name set differs from the expected managed skill set"

      for name in ${expectedSkillArgs}; do
        [ -d "$actual/$name" ] && [ ! -L "$actual/$name" ] \
          || fail "invalid skill root: $name"
        [ -f "$actual/$name/SKILL.md" ] && [ ! -L "$actual/$name/SKILL.md" ] \
          || fail "missing regular SKILL.md: $name"
      done

      skill_creator="$actual/skill-creator"
      for script in ${skillCreatorScriptArgs}; do
        [ -x "$skill_creator/scripts/$script" ] \
          || fail "skill-creator entrypoint is not executable: $script"
        head -n 1 "$skill_creator/scripts/$script" \
          | grep -Fx '#!${skillCreatorPython}/bin/python3' >/dev/null \
          || fail "skill-creator entrypoint lacks its managed interpreter: $script"
      done

      "$skill_creator/scripts/quick_validate.py" "$skill_creator" \
        || fail "installed skill-creator validator failed"
      "$skill_creator/scripts/init_skill.py" generated-skill \
        --path "$TMPDIR/generated" \
        || fail "installed skill-creator initializer failed"
      [ -f "$TMPDIR/generated/generated-skill/SKILL.md" ] \
        || fail "installed skill-creator initializer omitted SKILL.md"
      package_input="$TMPDIR/package-input"
      mkdir "$package_input"
      cp -R -- "$skill_creator" "$package_input/skill-creator"
      "$skill_creator/scripts/package_skill.py" \
        "$package_input/skill-creator" "$TMPDIR/dist" \
        || fail "installed skill-creator packager failed"
      [ -f "$TMPDIR/dist/skill-creator.zip" ] \
        || fail "installed skill-creator packager omitted its archive"

      for name in git-surgeon; do
        [ -f "$actual/$name/LICENSE" ] && [ ! -L "$actual/$name/LICENSE" ] \
          || fail "missing regular injected LICENSE: $name"
      done

      [ -f "$actual/translate-en/GLOSSARY.csv" ] \
        && [ ! -L "$actual/translate-en/GLOSSARY.csv" ] \
        || fail "translate-en glossary was not materialized"

      for name in ${ponytailSkillArgs}; do
        if find -P "$actual/$name" -mindepth 1 \
          \( -path '*/hooks/*' -o -name '*runtime*' -o -name '*statusline*' \
             -o -name '*bundle-receipt*' -o -path '*/.opencode/*' \
             -o -path '*/plugins/*' -o -path '*/commands/*' \
             -o -path '*/pi-extension/*' -o -path '*/ponytail-mcp/*' \) \
          -print -quit | grep -q .; then
          fail "excluded Ponytail payload appears under $name"
        fi
      done

      write_manifest "$expected" "$TMPDIR/expected.manifest"
      write_manifest "$actual" "$TMPDIR/actual.manifest"
      cmp "$TMPDIR/expected.manifest" "$TMPDIR/actual.manifest" \
        || fail "framed path/type/mode/link/content manifests differ"

      [ ! -e ${resources}/share/agent-resources/prompts/bigpowers ] \
        || fail "retired BigPowers prompt root is still packaged"

      extensions=${resources}/share/agent-resources/pi-extensions
      [ ! -e "$extensions/pi-subagent" ] && [ ! -L "$extensions/pi-subagent" ] \
        || fail "retired pi-subagent root is still packaged"
      missing_extensions=
      for name in pi-mcp-adapter pi-openai-server-compaction pi-quiet; do
        if [ ! -d "$extensions/$name" ] || [ -L "$extensions/$name" ]; then
          missing_extensions="$missing_extensions $name"
        fi
      done
      [ -z "$missing_extensions" ] \
        || fail "missing Pi extension roots:$missing_extensions"

      ${lib.optionalString (!havePiSources) ''
        fail "Pi extension roots exist but pinned source inputs are unavailable"
      ''}

      ${lib.optionalString havePiSources ''
        mcp="$extensions/pi-mcp-adapter"
        openai_compaction="$extensions/pi-openai-server-compaction"
        quiet="$extensions/pi-quiet"

        validate_tree "$mcp"
        validate_tree "$openai_compaction"
        validate_tree "$quiet"

        quiet_expected="$TMPDIR/pi-quiet-expected"
        mkdir -p "$quiet_expected/src"
        for relative in ${piQuietFileArgs}; do
          cp -a -- ${lib.escapeShellArg "${piQuiet}/packages/pi-quiet"}/"$relative" \
            "$quiet_expected/$relative"
        done
        cp -a -- ${lib.escapeShellArg "${piQuiet}/LICENSE"} "$quiet_expected/LICENSE"
        ${pkgs.buildPackages.patch}/bin/patch --force --fuzz=0 --no-backup-if-mismatch \
          --directory="$quiet_expected" --strip=1 \
          < ${../../packages/agent-resources/pi-quiet-bounded-history.patch}

        openai_compaction_expected="$TMPDIR/pi-openai-server-compaction-expected"
        mkdir -p "$openai_compaction_expected/src" \
          "$openai_compaction_expected/node_modules/ws"
        for relative in ${piOpenaiServerCompactionFileArgs}; do
          cp -a -- ${lib.escapeShellArg "${piOpenaiServerCompaction}"}/"$relative" \
            "$openai_compaction_expected/$relative"
        done
        cp -a -- \
          ${../../packages/agent-resources/pi-openai-server-compaction-active-history.ts} \
          "$openai_compaction_expected/src/active-history.ts"
        cp -a -- ${lib.escapeShellArg "${wsSource}"}/. \
          "$openai_compaction_expected/node_modules/ws"/
        ${pkgs.buildPackages.patch}/bin/patch --force --fuzz=0 --no-backup-if-mismatch \
          --directory="$openai_compaction_expected" --strip=1 \
          < ${../../packages/agent-resources/pi-openai-server-compaction-bounded-history.patch}

        find "$quiet_expected" "$openai_compaction_expected" -type d \
          -exec chmod 0555 {} +

        write_manifest "$quiet_expected" "$TMPDIR/expected-quiet.manifest"
        write_manifest "$quiet" "$TMPDIR/actual-quiet.manifest"
        cmp "$TMPDIR/expected-quiet.manifest" "$TMPDIR/actual-quiet.manifest" \
          || fail "pi-quiet framed path/type/mode/link/content manifest differs"

        write_manifest "$openai_compaction_expected" \
          "$TMPDIR/expected-openai-compaction.manifest"
        write_manifest "$openai_compaction" \
          "$TMPDIR/actual-openai-compaction.manifest"
        cmp "$TMPDIR/expected-openai-compaction.manifest" \
          "$TMPDIR/actual-openai-compaction.manifest" \
          || fail "pi-openai-server-compaction framed manifest differs"

        runtime_root="$TMPDIR/pi-extension-runtime"
        runtime_quiet="$runtime_root/pi-quiet"
        runtime_openai="$runtime_root/pi-openai-server-compaction"
        mkdir -p "$runtime_quiet" "$runtime_openai"
        cp -R -- "$quiet"/. "$runtime_quiet"/
        cp -R -- "$openai_compaction"/. "$runtime_openai"/
        chmod -R u+w "$runtime_root"

        pi_runtime=${lib.escapeShellArg "${piPackage}/lib/node_modules/@earendil-works/pi-coding-agent"}
        link_pi_runtime() {
          root=$1
          mkdir -p "$root/node_modules/@earendil-works"
          ln -s "$pi_runtime" \
            "$root/node_modules/@earendil-works/pi-coding-agent"
          for peer in pi-agent-core pi-ai pi-tui; do
            ln -s "$pi_runtime/node_modules/@earendil-works/$peer" \
              "$root/node_modules/@earendil-works/$peer"
          done
        }
        link_pi_runtime "$runtime_quiet"
        link_pi_runtime "$runtime_openai"

        mkdir -p "$runtime_openai/node_modules/@types"
        ln -s "$pi_runtime/node_modules/@types/node" \
          "$runtime_openai/node_modules/@types/node"
        ln -s ${lib.escapeShellArg wsTypes} \
          "$runtime_openai/node_modules/@types/ws"

        mkdir -p "$TMPDIR/runtime-home" "$TMPDIR/runtime-agent"
        HOME="$TMPDIR/runtime-home" PI_CODING_AGENT_DIR="$TMPDIR/runtime-agent" \
          node --experimental-strip-types \
          ${./pi-agent-resources-bounded-history.check.mjs} \
          "$runtime_quiet/src/index.ts" "$runtime_quiet/src/compaction.ts" \
          "$runtime_openai/src/index.ts" \
          "$runtime_openai/src/active-history.ts" \
          "$runtime_openai/src/custom-stream.ts" \
          "$runtime_openai/src/openai-ws-stream.ts" \
          "$runtime_openai/src/state.ts"

        (
          cd "$runtime_openai"
          tsc \
            --allowImportingTsExtensions \
            --module NodeNext \
            --moduleResolution NodeNext \
            --noEmit \
            --pretty false \
            --skipLibCheck \
            --strict \
            --target ES2022 \
            --types node \
            src/*.ts
        )

        for relative in ${piQuietPackagedFileArgs}; do
          [ -f "$quiet/$relative" ] && [ ! -L "$quiet/$relative" ] \
            || fail "missing regular pi-quiet file: $relative"
        done

        jq -e '
          .name == "@zenspc/pi-quiet"
          and .type == "module"
          and .license == "MIT"
          and .pi.extensions == ["./src/index.ts"]
          and (.dependencies // {}) == {}
          and ((.scripts // {})
            | (has("preinstall") or has("install") or has("postinstall") or has("prepare"))
            | not)
        ' "$quiet/package.json" >/dev/null \
          || fail "invalid pi-quiet package manifest"

        jq -e '
          .name == "pi-openai-server-compaction"
          and .private == true
          and .type == "module"
          and .license == "MIT"
          and .pi.extensions == ["./src/index.ts"]
          and ((.scripts // {})
            | (has("preinstall") or has("install") or has("postinstall") or has("prepare"))
            | not)
        ' "$openai_compaction/package.json" >/dev/null \
          || fail "invalid pi-openai-server-compaction package manifest"

        jq -e '
          .name == "ws"
          and .version == ${builtins.toJSON piSources.ws.version}
          and .license == "MIT"
          and (.dependencies // {}) == {}
        ' "$openai_compaction/node_modules/ws/package.json" >/dev/null \
          || fail "invalid pi-openai-server-compaction ws closure"

        quiet_test_root="$TMPDIR/pi-quiet-tests"
        mkdir "$quiet_test_root"
        cp -R -- ${lib.escapeShellArg "${piQuiet}/packages/pi-quiet"}/. \
          "$quiet_test_root"/
        chmod -R u+w "$quiet_test_root"
        ${pkgs.buildPackages.patch}/bin/patch --force --fuzz=0 --no-backup-if-mismatch \
          --directory="$quiet_test_root" --strip=1 \
          < ${../../packages/agent-resources/pi-quiet-bounded-history.patch}
        node --experimental-strip-types --test \
          "$quiet_test_root"/src/*.test.ts

        # This proves only that both entrypoints load under the packaged Pi.
        # It does not override the compaction extension's incompatible peer range.
        pi_smoke="$TMPDIR/pi-entrypoint-smoke"
        mkdir -p "$pi_smoke/home" "$pi_smoke/agent"

        run_pi_entrypoint_smoke() {
          entrypoint=$1
          output=$2
          (
            cd "$pi_smoke/home"
            HOME="$pi_smoke/home" PI_CODING_AGENT_DIR="$pi_smoke/agent" PI_OFFLINE=1 \
              ${lib.getExe piPackage} \
              --mode rpc --no-session --offline \
              --no-extensions --no-skills --no-prompt-templates \
              --no-context-files --no-approve \
              --extension "$entrypoint" </dev/null >"$output" 2>&1
          )
        }

        quiet_smoke_output="$pi_smoke/pi-quiet.log"
        run_pi_entrypoint_smoke "$quiet/src/index.ts" "$quiet_smoke_output" \
          || { cat "$quiet_smoke_output" >&2; fail "pi-quiet entrypoint failed to load"; }

        compaction_smoke_output="$pi_smoke/pi-openai-server-compaction.log"
        run_pi_entrypoint_smoke \
          "$openai_compaction/src/index.ts" "$compaction_smoke_output" \
          || { cat "$compaction_smoke_output" >&2; fail "pi-openai-server-compaction entrypoint failed to load"; }

        invalid_smoke_output="$pi_smoke/invalid-extension.log"
        if run_pi_entrypoint_smoke \
          "$openai_compaction/src/config.ts" "$invalid_smoke_output"; then
          fail "Pi RPC smoke accepted an extension without a factory export"
        fi
        grep -F "Extension does not export a valid factory function" \
          "$invalid_smoke_output" >/dev/null \
          || { cat "$invalid_smoke_output" >&2; fail "Pi RPC smoke failed for an unrelated reason"; }

        node --experimental-import-meta-resolve --experimental-strip-types \
          --input-type=module -e '
          import fs from "node:fs";
          import path from "node:path";
          import { pathToFileURL } from "node:url";
          const root = process.argv[1];
          const wsRoot = fs.realpathSync(path.join(root, "node_modules/ws"));
          const resolved = import.meta.resolve("ws", pathToFileURL(path.join(root, "src/index.ts")));
          const real = fs.realpathSync(new URL(resolved));
          if (real !== wsRoot && !real.startsWith(wsRoot + path.sep)) {
            throw new Error("ws resolution escaped packaged closure: " + real);
          }
          const module = await import(pathToFileURL(path.join(root, "src/openai-ws-connection.ts")));
          if (typeof module.OpenAIWebSocketManager !== "function") {
            throw new Error("OpenAIWebSocketManager export is missing");
          }
        ' "$openai_compaction"

        printf '%s\0' ${piMcpTopLevelArgs} \
          | sort -z >"$TMPDIR/expected-mcp-top-level"
        find -P "$mcp" -mindepth 1 -maxdepth 1 -printf '%f\0' \
          | sort -z >"$TMPDIR/actual-mcp-top-level"
        cmp "$TMPDIR/expected-mcp-top-level" "$TMPDIR/actual-mcp-top-level" \
          || fail "pi-mcp-adapter packaged file set differs"

        mcp_config_expected_root="$TMPDIR/pi-mcp-adapter-expected"
        mkdir "$mcp_config_expected_root"
        cp ${lib.escapeShellArg "${piMcpAdapter}/config.ts"} \
          "$mcp_config_expected_root/config.ts"
        chmod u+w "$mcp_config_expected_root/config.ts"
        ${pkgs.buildPackages.patch}/bin/patch --force --fuzz=0 --no-backup-if-mismatch \
          --directory="$mcp_config_expected_root" --strip=1 \
          < ${../../packages/agent-resources/pi-mcp-adapter-xdg-config-home.patch}
        mcp_config_expected="$mcp_config_expected_root/config.ts"

        mcp_package_expected="$TMPDIR/pi-mcp-package.json"
        ${pkgs.python3}/bin/python3 - \
          ${lib.escapeShellArg "${piMcpAdapter}/package.json"} \
          "$mcp_package_expected" <<'PY'
        import json
        from pathlib import Path
        import sys

        package = json.loads(Path(sys.argv[1]).read_text())
        package.pop("devDependencies", None)
        package.pop("scripts", None)
        Path(sys.argv[2]).write_text(json.dumps(package, indent=2) + "\n")
        PY

        for relative in ${piMcpFileArgs}; do
          [ -f "$mcp/$relative" ] && [ ! -L "$mcp/$relative" ] \
            || fail "missing regular pi-mcp-adapter file: $relative"
          expected_mcp_file=${lib.escapeShellArg "${piMcpAdapter}"}/"$relative"
          [ "$relative" != config.ts ] || expected_mcp_file=$mcp_config_expected
          [ "$relative" != package.json ] || expected_mcp_file=$mcp_package_expected
          cmp "$expected_mcp_file" "$mcp/$relative" \
            || fail "unexpected pi-mcp-adapter file: $relative"
        done

        test "$(grep -Fc 'state.config.settings?.mcpFooterStatus ?? "full"' \
          "$mcp/init.ts")" -eq 1 \
          || fail "pi-mcp-adapter native footer-status default changed"
        test "$(grep -Fc 'typeof theme?.fg === "function"' \
          "$mcp/init.ts")" -eq 1 \
          || fail "pi-mcp-adapter plain-theme footer fallback changed"

        [ -d "$mcp/skills" ] && [ ! -L "$mcp/skills" ] \
          || fail "missing regular pi-mcp-adapter skills root"
        write_manifest ${lib.escapeShellArg "${piMcpAdapter}/skills"} \
          "$TMPDIR/expected-mcp-skills.manifest"
        write_manifest "$mcp/skills" "$TMPDIR/actual-mcp-skills.manifest"
        cmp "$TMPDIR/expected-mcp-skills.manifest" \
          "$TMPDIR/actual-mcp-skills.manifest" \
          || fail "pi-mcp-adapter packaged skills differ"

        [ -d "$mcp/dist" ] && [ ! -L "$mcp/dist" ] \
          || fail "missing regular pi-mcp-adapter public dist root"
        printf '%s\0' ${piMcpPublicDistFileArgs} \
          | sort -z >"$TMPDIR/expected-mcp-dist"
        find -P "$mcp/dist" -mindepth 1 -maxdepth 1 -printf '%f\0' \
          | sort -z >"$TMPDIR/actual-mcp-dist"
        cmp "$TMPDIR/expected-mcp-dist" "$TMPDIR/actual-mcp-dist" \
          || fail "pi-mcp-adapter public dist differs"
        while IFS= read -r -d "" public_file; do
          [ -f "$mcp/dist/$public_file" ] && [ ! -L "$mcp/dist/$public_file" ] \
            || fail "invalid pi-mcp-adapter public dist file: $public_file"
        done <"$TMPDIR/expected-mcp-dist"

        public_fixture="$TMPDIR/pi-mcp-public-import"
        mkdir -p "$public_fixture/node_modules"
        ln -s "$mcp" "$public_fixture/node_modules/pi-mcp-adapter"
        (
          cd "$public_fixture"
          node --input-type=module -e '
            const metadata = await import("pi-mcp-adapter/metadata-cache");
            const config = await import("pi-mcp-adapter/config");
            const types = await import("pi-mcp-adapter/types");
            if (typeof metadata.isServerCacheValid !== "function") process.exit(2);
            if (typeof config.loadMcpConfig !== "function") process.exit(3);
            if (typeof types.formatToolName !== "function") process.exit(4);
          '
        ) || fail "pi-mcp-adapter public exports failed to load"

        jq -e '
          .name == "pi-mcp-adapter"
          and .version == ${builtins.toJSON piSources.pi-mcp-adapter.version}
          and .type == "module"
          and .bin == {"pi-mcp-adapter":"cli.js"}
          and .pi.extensions == ["./index.ts"]
          and (.devDependencies == null)
          and (.scripts == null)
          and (.files | index("dist")) != null
          and .exports["./types"] == {
            "types":"./dist/types.d.ts",
            "import":"./dist/types.js",
            "default":"./dist/types.js"
          }
          and .exports["./config"] == {
            "types":"./dist/config.d.ts",
            "import":"./dist/config.js",
            "default":"./dist/config.js"
          }
          and .exports["./metadata-cache"] == {
            "types":"./dist/metadata-cache.d.ts",
            "import":"./dist/metadata-cache.js",
            "default":"./dist/metadata-cache.js"
          }
        ' "$mcp/package.json" >/dev/null \
          || fail "invalid pi-mcp-adapter package manifest"

        node --experimental-import-meta-resolve ${piClosureCheck} \
          "$mcp" ${lib.escapeShellArg "${piMcpAdapter}/package-lock.json"}

        pi_mcp_runtime="$TMPDIR/pi-mcp-round-trip"
        mkdir -p \
          "$pi_mcp_runtime/home/.config/mcp" \
          "$pi_mcp_runtime/agent" \
          "$pi_mcp_runtime/project"
        install -m 600 ${piMcpRegistryFile} \
          "$pi_mcp_runtime/home/.config/mcp/mcp.json"
        (
          cd "$pi_mcp_runtime/project"
          BASH_ENV=/forbidden \
            DEFAULT_MODEL=parent-poison \
            GEMINI_API_KEY=other-provider-sentinel \
            GIT_AI_SOCKET=/forbidden \
            GIT_TRACE2_EVENT=/forbidden \
            HOME="$pi_mcp_runtime/home" \
            XDG_CONFIG_HOME="$pi_mcp_runtime/home/.config" \
            NODE_OPTIONS=--trace-warnings \
            NIX_SSL_CERT_FILE=/managed-ca \
            OPENAI_API_KEY=typed-sentinel \
            PI_CODING_AGENT_DIR="$pi_mcp_runtime/agent" \
            PI_OFFLINE=1 \
            PYTHONPATH=/forbidden \
            SSH_AUTH_SOCK=/forbidden \
            UNRELATED_SECRET=unrelated-sentinel \
            ${pkgs.coreutils}/bin/timeout --signal=KILL 60s \
            ${lib.getExe piPackage} \
              --print --offline --no-session --no-context-files \
              --no-extensions --no-skills --no-prompt-templates --no-approve \
              --extension "$mcp/index.ts" \
              --extension ${piMcpSyntheticProvider} \
              --provider synthetic-mcp --model target \
              "exercise the managed MCP environment" \
              >"$pi_mcp_runtime/stdout" 2>"$pi_mcp_runtime/stderr"
        ) || {
          cat "$pi_mcp_runtime/stdout" >&2
          cat "$pi_mcp_runtime/stderr" >&2
          fail "Pi managed MCP round trip failed"
        }
        grep -Fx 'pi-mcp-round-trip-ok' "$pi_mcp_runtime/stdout" >/dev/null || {
          cat "$pi_mcp_runtime/stdout" >&2
          cat "$pi_mcp_runtime/stderr" >&2
          fail "Pi did not complete the managed MCP round trip"
        }
      ''}

      mkdir -p "$out"
      printf '%s\n' ${expectedSkillArgs} >"$out/skills.txt"
    ''
