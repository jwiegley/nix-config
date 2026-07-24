{
  pkgs,
  bigpowers ? null,
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

  bigpowersResources = import ../../config/ai/bigpowers-resources.nix;
  bigpowersSkills = bigpowersResources.names;

  ponytailSkills = [
    "ponytail"
    "ponytail-review"
    "ponytail-audit"
    "ponytail-debt"
    "ponytail-gain"
    "ponytail-help"
  ];

  expectedSkills =
    bigpowersSkills
    ++ ponytailSkills
    ++ [
      "git-surgeon"
      "translate-en"
    ];

  resources = pkgs.agent-resources;
  haveSources =
    bigpowers != null && ponytail != null && translate-tool != null && gitSurgeonSource != null;
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

  wsSource = pkgs.fetchzip {
    url = "https://registry.npmjs.org/ws/-/ws-8.18.3.tgz";
    hash = "sha256-+o96RaViEX6JAoRI5JCLDJDcIXj+XbaH0+wSM9F2pBw=";
  };

  piMcpFiles = [
    "cli.js"
    "agent-dir.ts"
    "index.ts"
    "error-signal.ts"
    "state.ts"
    "utils.ts"
    "abort.ts"
    "tool-metadata.ts"
    "init.ts"
    "ui-session.ts"
    "proxy-modes.ts"
    "direct-tools.ts"
    "commands.ts"
    "onboarding-state.ts"
    "mcp-setup-panel.ts"
    "types.ts"
    "ui-stream-types.ts"
    "config.ts"
    "server-manager.ts"
    "sampling-handler.ts"
    "elicitation-handler.ts"
    "tool-registrar.ts"
    "tool-result-renderer.ts"
    "mcp-output-guard.ts"
    "resource-tools.ts"
    "lifecycle.ts"
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

  expectedPins = [
    {
      name = "bigpowers revision";
      actual = bigpowers.rev or null;
      expected = bigpowersResources.revision;
    }
    {
      name = "bigpowers NAR hash";
      actual = bigpowers.narHash or null;
      expected = bigpowersResources.narHash;
    }
    {
      name = "bigpowers package manifest hash";
      actual = builtins.hashFile "sha256" "${bigpowers}/package.json";
      expected = "b95b2a687178b1d7314cc5cd66f6655269565b54abd139bc7b314c096aa3ddfb";
    }
    {
      name = "bigpowers Pi manifest hash";
      actual = builtins.hashFile "sha256" "${bigpowers}/.pi/package.json";
      expected = "3546705df79cc06abfb92ca3f97b01592da4c30bb7d837db496551401c9979a2";
    }
    {
      name = "bigpowers license hash";
      actual = builtins.hashFile "sha256" "${bigpowers}/LICENSE";
      expected = "ab5c332485a9ffad649f5a341d5ecfd35abff52249bf2a5c958f168a002ce376";
    }
    {
      name = "ponytail revision";
      actual = ponytail.rev or null;
      expected = "16f29800fd2681bdf24f3eb4ccffe38be3baec6b";
    }
    {
      name = "ponytail NAR hash";
      actual = ponytail.narHash or null;
      expected = "sha256-Y7d4s7uqjH6IbEXhqAiQ+yaxr6iiGcv2X64LuMtG1T8=";
    }
    {
      name = "translate-tool revision";
      actual = translate-tool.rev or null;
      expected = "bffdb7ba3e5db603ea1390fee555354c1d45d642";
    }
    {
      name = "translate-tool NAR hash";
      actual = translate-tool.narHash or null;
      expected = "sha256-P27Hvn8p1+BN8z6g/aFk91BFtL9SMQiMNFYayKn5xyY=";
    }
    {
      name = "llm-agents Pi version";
      actual = piPackage.version or null;
      expected = "0.81.1";
    }
  ]
  ++ lib.optionals havePiSources [
    {
      name = "pi-mcp-adapter revision";
      actual = piMcpAdapter.rev or null;
      expected = "82724dccc13a49310530898f922bafff12b7f3fe";
    }
    {
      name = "pi-mcp-adapter NAR hash";
      actual = piMcpAdapter.narHash or null;
      expected = "sha256-JjYS9tPSoVuubdmHTqTNNYfDJOc9CBPvVbIxvdJWi7M=";
    }
    {
      name = "pi-mcp-adapter lock hash";
      actual = builtins.hashFile "sha256" "${piMcpAdapter}/package-lock.json";
      expected = "156cd7b65090cb5600651b40563dea3974fbeeaa7dbb6346f3deb0e9e0528bd0";
    }
    {
      name = "pi-openai-server-compaction revision";
      actual = piOpenaiServerCompaction.rev or null;
      expected = "c6d593087709e9481223dc6c6c2269b371b5e055";
    }
    {
      name = "pi-openai-server-compaction NAR hash";
      actual = piOpenaiServerCompaction.narHash or null;
      expected = "sha256-SFGcISdYblxGonhipIHPAOons8MdwYtu+A+WbHnNSVg=";
    }
    {
      name = "pi-openai-server-compaction manifest hash";
      actual = builtins.hashFile "sha256" "${piOpenaiServerCompaction}/package.json";
      expected = "f9cf0b5aaa73c1a3cf4ed92ba55c4c9f2784e46ef39c29822b279f3410452110";
    }
    {
      name = "pi-quiet revision";
      actual = piQuiet.rev or null;
      expected = "b281afef4e61188e7aa76aaa114ba505274fa7bc";
    }
    {
      name = "pi-quiet NAR hash";
      actual = piQuiet.narHash or null;
      expected = "sha256-CScA35fG/xSgtJrWGf36G5oEv3Y+P5sSHjsy4NXkL94=";
    }
    {
      name = "pi-quiet manifest hash";
      actual = builtins.hashFile "sha256" "${piQuiet}/packages/pi-quiet/package.json";
      expected = "1b370c62fdf7b3b5a9fb35b45ba0cf0e3ceefa35e037f7cd9911b816ad03e4fa";
    }
  ];

  badPins = builtins.filter (pin: pin.actual != pin.expected) expectedPins;
  badPinMessage = lib.concatMapStringsSep ", " (
    pin: "${pin.name}: expected ${pin.expected}, got ${toString pin.actual}"
  ) badPins;

  expectedSkillArgs = lib.escapeShellArgs expectedSkills;
  bigpowersSkillArgs = lib.escapeShellArgs bigpowersSkills;
  ponytailSkillArgs = lib.escapeShellArgs ponytailSkills;

  copyBigpowersExpected = lib.concatMapStringsSep "\n" (name: ''
    copy_expected_tree ${lib.escapeShellArg "${bigpowers}/.pi/skills/${name}"} "$expected/${name}"
    cp -a -- ${lib.escapeShellArg "${bigpowers}/LICENSE"} "$expected/${name}/LICENSE"
    chmod --reference=${lib.escapeShellArg "${bigpowers}/.pi/skills/${name}"} "$expected/${name}"
  '') bigpowersSkills;

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

    const expectedDirect = {
      "@earendil-works/pi-ai": "0.74.2",
      "@earendil-works/pi-tui": "0.74.2",
      "@modelcontextprotocol/ext-apps": "1.7.4",
      "@modelcontextprotocol/sdk": "1.29.0",
      "open": "10.2.0",
      "recheck": "4.5.0",
      "typebox": "1.3.3",
      "zod": "4.4.3"
    };
    for (const [name, version] of Object.entries(expectedDirect)) {
      const key = "node_modules/" + name;
      if (locked.get(key)?.version !== version) {
        fail("unexpected locked version for " + name);
      }
      if (!actual.has(key)) fail("missing direct runtime dependency: " + name);
    }

    const runtimeImports = [
      "@earendil-works/pi-ai",
      "@earendil-works/pi-tui",
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
      "typebox",
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
else if badPins != [ ] then
  throw "agent-resources source pin mismatch: ${badPinMessage}"
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

      ${copyBigpowersExpected}
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
        || fail "skill name set differs from the expected Bigpowers replacement set"

      for name in ${expectedSkillArgs}; do
        [ -d "$actual/$name" ] && [ ! -L "$actual/$name" ] \
          || fail "invalid skill root: $name"
        [ -f "$actual/$name/SKILL.md" ] && [ ! -L "$actual/$name/SKILL.md" ] \
          || fail "missing regular SKILL.md: $name"
      done

      for name in ${bigpowersSkillArgs} git-surgeon; do
        [ -f "$actual/$name/LICENSE" ] && [ ! -L "$actual/$name/LICENSE" ] \
          || fail "missing regular injected LICENSE: $name"
      done

      [ -f "$actual/translate-en/GLOSSARY.csv" ] \
        && [ ! -L "$actual/translate-en/GLOSSARY.csv" ] \
        || fail "translate-en glossary was not materialized"

      test "$(sha256sum ${lib.escapeShellArg "${gitSurgeonSource}/skills/git-surgeon/SKILL.md"} | cut -d' ' -f1)" \
        = 086445cd0424c46022c7c23912c82ebb43d168e11b3a13141669149bdba6f8bc
      test "$(sha256sum ${lib.escapeShellArg "${gitSurgeonSource}/LICENSE"} | cut -d' ' -f1)" \
        = dfc0be306ac621b63914bf0f4854538a2e0a8d09ad24f20e7edd9a80ece241b2
      test "$(sha256sum ${lib.escapeShellArg "${translate-tool}/skill/SKILL.md"} | cut -d' ' -f1)" \
        = f26ff06e43b9d99e96876cbd567a7f6d8585983b0a550b97ef5e672f294790fb
      test "$(sha256sum ${lib.escapeShellArg "${translate-tool}/glossary.csv"} | cut -d' ' -f1)" \
        = 8eab769223267b8b8cded5ba62f7a4250dfcf25d94d35cffd7e360354b3e9523

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

      actual_prompts=${resources}/share/agent-resources/prompts/bigpowers
      expected_prompts="$TMPDIR/expected-prompts"
      mkdir "$expected_prompts"
      for name in ${bigpowersSkillArgs}; do
        cp -a -- ${lib.escapeShellArg "${bigpowers}/.pi/prompts"}/"$name.md" \
          "$expected_prompts/$name.md"
      done
      write_manifest "$expected_prompts" "$TMPDIR/expected-prompts.manifest"
      write_manifest "$actual_prompts" "$TMPDIR/actual-prompts.manifest"
      cmp "$TMPDIR/expected-prompts.manifest" "$TMPDIR/actual-prompts.manifest" \
        || fail "Bigpowers prompt manifest differs"

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
          and .version == "0.4.0"
          and .type == "module"
          and .license == "MIT"
          and .peerDependencies == {
            "@earendil-works/pi-coding-agent": "*",
            "@earendil-works/pi-tui": "*"
          }
          and .pi.extensions == ["./src/index.ts"]
          and (.dependencies // {}) == {}
          and ((.scripts // {})
            | (has("preinstall") or has("install") or has("postinstall") or has("prepare"))
            | not)
        ' "$quiet/package.json" >/dev/null \
          || fail "invalid pi-quiet package manifest"

        jq -e '
          .name == "pi-openai-server-compaction"
          and .version == "0.1.0"
          and .private == true
          and .type == "module"
          and .license == "MIT"
          and .engines.node == ">=22"
          and .dependencies == {"ws":"^8.18.0"}
          and .peerDependencies == {
            "@earendil-works/pi-agent-core": ">=0.80.9 <0.81.0",
            "@earendil-works/pi-ai": ">=0.80.9 <0.81.0",
            "@earendil-works/pi-coding-agent": ">=0.80.9 <0.81.0"
          }
          and .pi.extensions == ["./src/index.ts"]
          and ((.scripts // {})
            | (has("preinstall") or has("install") or has("postinstall") or has("prepare"))
            | not)
        ' "$openai_compaction/package.json" >/dev/null \
          || fail "invalid pi-openai-server-compaction package manifest"

        jq -e '
          .name == "ws"
          and .version == "8.18.3"
          and .license == "MIT"
          and .engines.node == ">=10.0.0"
          and (.dependencies // {}) == {}
          and .peerDependencies == {
            "bufferutil": "^4.0.1",
            "utf-8-validate": ">=5.0.2"
          }
          and .peerDependenciesMeta == {
            "bufferutil": {"optional":true},
            "utf-8-validate": {"optional":true}
          }
        ' "$openai_compaction/node_modules/ws/package.json" >/dev/null \
          || fail "invalid pi-openai-server-compaction ws closure"

        test "$(sha256sum "$quiet/LICENSE" | cut -d' ' -f1)" \
          = fb5278571984b1db0ef5ef82656aac3a9f5ac607b3349cf27c6e220d62b66db1
        test "$(sha256sum "$quiet/src/index.ts" | cut -d' ' -f1)" \
          = 95dd3737e4d620a4d0895bb8e4ea521b9dec13483c8c73ee6045310bd5978661
        test "$(sha256sum "$openai_compaction/LICENSE.md" | cut -d' ' -f1)" \
          = 0d4484983377237e9aa2a3e4192087c3bbccc196223fc098d0bca60d25f78577
        test "$(sha256sum "$openai_compaction/src/index.ts" | cut -d' ' -f1)" \
          = 477adf73e0bd37047f3f597531a49528e122312c9c2590874a7caf283ed19607
        test "$(sha256sum "$openai_compaction/node_modules/ws/package.json" | cut -d' ' -f1)" \
          = aaedef2a72b60db8fb36d9b46c48d44986051785a2b6450c62994603c85dd959

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

        for relative in ${piMcpFileArgs}; do
          [ -f "$mcp/$relative" ] && [ ! -L "$mcp/$relative" ] \
            || fail "missing regular pi-mcp-adapter file: $relative"
          cmp ${lib.escapeShellArg "${piMcpAdapter}"}/"$relative" "$mcp/$relative" \
            || fail "modified pi-mcp-adapter file: $relative"
        done

        jq -e '
          .name == "pi-mcp-adapter"
          and .version == "2.11.0"
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
