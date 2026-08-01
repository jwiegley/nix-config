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
    "translate-en"
  ];

  resources = pkgs.agent-resources;
  haveSources = ponytail != null && translate-tool != null && gitSurgeonSource != null;
  havePiSources = piMcpAdapter != null && piOpenaiServerCompaction != null && piQuiet != null;

  piQuietFiles = [
    "package.json"
    "CHANGELOG.md"
    "README.md"
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

  piMcpFiles = [
    "cli.js"
    "agent-dir.ts"
    "index.ts"
    "error-signal.ts"
    "state.ts"
    "utils.ts"
    "abort.ts"
    "runtime-owner.ts"
    "tool-metadata.ts"
    "init.ts"
    "ui-session.ts"
    "proxy-modes.ts"
    "direct-tools.ts"
    "commands.ts"
    "prompts.ts"
    "onboarding-state.ts"
    "mcp-setup-panel.ts"
    "types.ts"
    "ui-stream-types.ts"
    "config.ts"
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
    "oauth-handler.ts"
    "mcp-auth.ts"
    "mcp-oauth-provider.ts"
    "mcp-callback-server.ts"
    "mcp-auth-flow.ts"
    "mcp-panel.ts"
    "panel-keys.ts"
    "mcp-trace.ts"
    "logger.ts"
    "errors.ts"
    "app-bridge.bundle.js"
    "banner.png"
    "README.md"
    "CHANGELOG.md"
    "LICENSE"
  ];

  piMcpFileArgs = lib.escapeShellArgs ([ "package.json" ] ++ piMcpFiles);
  piQuietFileArgs = lib.escapeShellArgs piQuietFiles;
  piQuietPackagedFileArgs = lib.escapeShellArgs (piQuietFiles ++ [ "LICENSE" ]);
  piOpenaiServerCompactionFileArgs = lib.escapeShellArgs piOpenaiServerCompactionFiles;

  expectedSkillArgs = lib.escapeShellArgs expectedSkills;
  ponytailSkillArgs = lib.escapeShellArgs ponytailSkills;

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

        openai_compaction_expected="$TMPDIR/pi-openai-server-compaction-expected"
        mkdir -p "$openai_compaction_expected/src" \
          "$openai_compaction_expected/node_modules/ws"
        for relative in ${piOpenaiServerCompactionFileArgs}; do
          cp -a -- ${lib.escapeShellArg "${piOpenaiServerCompaction}"}/"$relative" \
            "$openai_compaction_expected/$relative"
        done
        cp -a -- ${lib.escapeShellArg "${wsSource}"}/. \
          "$openai_compaction_expected/node_modules/ws"/

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

        node --experimental-strip-types --test \
          ${lib.escapeShellArg "${piQuiet}/packages/pi-quiet/src"}/*.test.ts

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

        printf '%s\0' ${piMcpFileArgs} node_modules \
          | sort -z >"$TMPDIR/expected-mcp-top-level"
        find -P "$mcp" -mindepth 1 -maxdepth 1 -printf '%f\0' \
          | sort -z >"$TMPDIR/actual-mcp-top-level"
        cmp "$TMPDIR/expected-mcp-top-level" "$TMPDIR/actual-mcp-top-level" \
          || fail "pi-mcp-adapter packaged file set differs"

        mcp_init_expected="$TMPDIR/pi-mcp-init.ts"
        cp ${lib.escapeShellArg "${piMcpAdapter}/init.ts"} "$mcp_init_expected"
        chmod u+w "$mcp_init_expected"
        ${pkgs.python3}/bin/python3 \
          ${../../packages/pi-mcp-adapter-normalize.py} "$mcp_init_expected"

        mcp_package_expected="$TMPDIR/pi-mcp-package.json"
        ${pkgs.python3}/bin/python3 - \
          ${lib.escapeShellArg "${piMcpAdapter}/package.json"} \
          "$mcp_package_expected" <<'PY'
        import json
        from pathlib import Path
        import sys

        package = json.loads(Path(sys.argv[1]).read_text())
        package.pop("devDependencies", None)
        Path(sys.argv[2]).write_text(json.dumps(package, indent=2) + "\n")
        PY

        for relative in ${piMcpFileArgs}; do
          [ -f "$mcp/$relative" ] && [ ! -L "$mcp/$relative" ] \
            || fail "missing regular pi-mcp-adapter file: $relative"
          expected_mcp_file=${lib.escapeShellArg "${piMcpAdapter}"}/"$relative"
          [ "$relative" != init.ts ] || expected_mcp_file=$mcp_init_expected
          [ "$relative" != package.json ] || expected_mcp_file=$mcp_package_expected
          cmp "$expected_mcp_file" "$mcp/$relative" \
            || fail "unexpected pi-mcp-adapter file: $relative"
        done

        grep -F 'footerStatus === "compact"' "$mcp/init.ts" >/dev/null \
          && grep -F 'connectedCount' "$mcp/init.ts" >/dev/null \
          && grep -F 'enabledCount' "$mcp/init.ts" >/dev/null \
          || fail "pi-mcp-adapter status renderer is not compact"

        jq -e '
          .name == "pi-mcp-adapter"
          and .version == ${builtins.toJSON piSources.pi-mcp-adapter.version}
          and .type == "module"
          and .bin == {"pi-mcp-adapter":"cli.js"}
          and .pi.extensions == ["./index.ts"]
          and ((.scripts // {})
            | (has("preinstall") or has("install") or has("postinstall") or has("prepare"))
            | not)
        ' "$mcp/package.json" >/dev/null \
          || fail "invalid pi-mcp-adapter package manifest"

        node --experimental-import-meta-resolve ${piClosureCheck} \
          "$mcp" ${lib.escapeShellArg "${piMcpAdapter}/package-lock.json"}
      ''}

      mkdir -p "$out"
      printf '%s\n' ${expectedSkillArgs} >"$out/skills.txt"
    ''
