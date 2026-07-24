{
  bun,
  coreutils,
  jq,
  lib,
  nodejs_22,
  piPackage,
  piPackages,
  runCommand,
  tmux,
}:

let
  root = package: name: "${package}/share/pi-packages/${name}";
  roots = {
    bigpowers = root piPackages.bigpowers "bigpowers";
    btw = root piPackages.pi-btw "pi-btw";
    artifacts = root piPackages.pi-artifacts "pi-artifacts";
    insights = root piPackages.pi-insights "pi-insights";
    subagentura = root piPackages.pi-subagentura "pi-subagentura";
    hashline = root piPackages.pi-hashline-edit-pro "pi-hashline-edit-pro";
    web = root piPackages.pi-web-access "pi-web-access";
    lens = root piPackages.pi-lens "pi-lens";
    ponytail = root piPackages.pi-ponytail "pi-ponytail";
    workflows = root piPackages.pi-dynamic-workflows "pi-dynamic-workflows";
    browser = root piPackages.pi-agent-browser-native "pi-agent-browser-native";
    lean = root piPackages.pi-lean-ctx "pi-lean-ctx";
  };
  gallery = "${piPackages.pi-gallery}/share/pi-gallery";
  quiet = "${piPackages.agent-resources}/share/agent-resources/pi-extensions/pi-quiet/src/index.ts";
  packageRoots = lib.escapeShellArgs (builtins.attrValues roots);
in
assert (piPackage.toolRendererWrapperAbi or null) == 1;
runCommand "pi-gallery-check"
  {
    nativeBuildInputs = [
      bun
      coreutils
      jq
      nodejs_22
      piPackages.pi-gallery.subagenturaTests
      tmux
    ];
  }
  ''
    set -euo pipefail

    fail() {
      echo "Pi gallery check: $*" >&2
      exit 1
    }

    expect_version() {
      manifest=$1
      expected=$2
      actual=$(jq -r .version "$manifest")
      [ "$actual" = "$expected" ] || fail "$manifest: expected $expected, got $actual"
    }

    expect_version ${roots.bigpowers}/package.json 2.82.3
    expect_version ${roots.btw}/package.json 0.4.1
    expect_version ${roots.artifacts}/package.json 0.9.0
    expect_version ${roots.insights}/package.json 1.0.1
    expect_version ${roots.subagentura}/package.json 3.0.3
    expect_version ${roots.hashline}/package.json 0.17.5
    expect_version ${roots.web}/package.json 0.13.0
    expect_version ${roots.lens}/package.json 3.8.71
    expect_version ${roots.ponytail}/package.json 4.8.4
    expect_version ${roots.workflows}/package.json 3.4.1
    expect_version ${roots.browser}/package.json 0.2.72
    expect_version ${roots.lean}/package.json 3.9.12

    for package_root in ${packageRoots}; do
      [ -f "$package_root/package.json" ] || fail "missing package manifest: $package_root"
      if [ -d "$package_root/node_modules" ]; then
        if find "$package_root/node_modules" -type d \
          \( -path '*/@earendil-works/*' -o -path '*/typebox' \) -print -quit | grep -q .; then
          fail "package bundles a Pi-provided peer runtime: $package_root"
        fi
      fi
    done

    [ "$(find ${roots.bigpowers}/.pi/skills -mindepth 1 -maxdepth 1 -type d | wc -l)" -eq 80 ]
    [ "$(find ${roots.bigpowers}/.pi/prompts -mindepth 1 -maxdepth 1 -type f -name '*.md' | wc -l)" -eq 80 ]

    [ -f ${roots.btw}/extensions/btw.ts ]
    [ -f ${roots.btw}/skills/btw/SKILL.md ]
    [ -f ${roots.artifacts}/extensions/index.ts ]
    [ -f ${roots.artifacts}/extensions/nix-bundle.js ]
    [ -f ${roots.artifacts}/skills/artifacts-authoring/SKILL.md ]
    [ -d ${roots.artifacts}/node_modules/mermaid ]
    [ -d ${roots.artifacts}/node_modules/markdown-it ]
    [ -f ${roots.insights}/index.ts ]
    [ -f ${roots.insights}/dist/index.html ]
    [ -d ${roots.insights}/node_modules/react ]
    [ -d ${roots.insights}/node_modules/recharts ]
    [ -f ${roots.subagentura}/src/subagent.ts ]
    [ -f ${roots.subagentura}/src/nix-bundle.js ]
    [ -f ${roots.subagentura}/src/nix-tmux-test-bundle.js ]
    [ -f ${roots.subagentura}/skills/ralplan/SKILL.md ]
    [ -d ${roots.subagentura}/node_modules/is-path-inside ]
    [ -d ${roots.subagentura}/node_modules/ndjson ]
    [ ! -e ${roots.subagentura}/node_modules/@earendil-works ]
    [ ! -e ${roots.subagentura}/node_modules/typebox ]

    substitute ${./pi-subagentura-tmux.test.ts} "$TMPDIR/pi-subagentura-tmux.test.ts" \
      --replace-fail '__SUBAGENTURA_ROOT__' ${roots.subagentura}
    PI_SUBAGENTURA_TMUX_SOCKET="nix-gallery-$$" \
      PI_SUBAGENTURA_TMUX_MARKER="$TMPDIR/subagentura-tmux-marker" \
      PATH=${lib.makeBinPath [ tmux ]}:$PATH \
      bun "$TMPDIR/pi-subagentura-tmux.test.ts" \
      | grep -Fx 'subagentura-tmux-contract-ok' >/dev/null

    [ -f ${roots.hashline}/index.ts ]
    [ ! -e ${roots.hashline}/node_modules/better-sqlite3 ]
    [ -d ${roots.hashline}/node_modules/sql.js ]
    [ -d ${roots.hashline}/node_modules/xxhash-wasm ]
    grep -F 'Bun standalone aborts before the native import can fall back' \
      ${roots.hashline}/src/hash-store.ts >/dev/null

    [ -f ${roots.web}/index.ts ]
    [ -f ${roots.web}/skills/librarian/SKILL.md ]
    grep -F 'PI_WEB_ACCESS_PROVIDER' ${roots.web}/index.ts >/dev/null \
      || fail "Web Access lacks the process-local provider policy"

    [ -f ${roots.lens}/dist/index.js ]
    [ "$(find ${roots.lens}/skills -mindepth 1 -maxdepth 1 -type d | wc -l)" -eq 4 ]
    [ "$(find ${roots.lens}/grammars -type f | wc -l)" -eq 24 ]
    ! grep -R -F 'autoInstall: true' ${roots.lens}/dist/clients >/dev/null \
      || fail "Lens still enables an auto-installer"
    grep -F 'disabled by Nix policy' ${roots.lens}/dist/clients/installer/index.js >/dev/null \
      || fail "Lens installer policy patch is missing"
    ! grep -R -E '"npx(\.cmd)?"' ${roots.lens}/dist >/dev/null \
      || fail "Lens still contains a live npx fallback"

    grep -F 'excludeSubagentTools: ["subagent"' \
      ${roots.workflows}/extensions/workflow.ts >/dev/null \
      || fail "Dynamic Workflows can recurse through the managed subagent tool"
    [ -f ${roots.workflows}/skills/workflow-authoring/SKILL.md ]
    [ -f ${roots.workflows}/skills/workflow-patterns/SKILL.md ]

    [ -f ${roots.ponytail}/pi-extension/index.js ]
    [ "$(find ${roots.ponytail}/skills -mindepth 1 -maxdepth 1 -type d | wc -l)" -eq 6 ]

    [ -f ${roots.browser}/dist/extensions/agent-browser/index.js ]
    [ -f ${roots.lean}/extensions/index.ts ]
    [ -f ${roots.lean}/extensions/vendor/mcp-sdk.cjs ]
    [ -f ${roots.lean}/LICENSE ]

    browser_version=$(${lib.getExe piPackages.agent-browser} --version)
    printf '%s\n' "$browser_version" | grep -F '0.33.0' >/dev/null \
      || fail "agent-browser version drifted: $browser_version"
    [ "$(${lib.getExe piPackages.lean-ctx} --version | head -1 | grep -c '3.9.12')" -eq 1 ]

    [ -f ${gallery}/index.ts ]
    [ -f ${gallery}/projection.json ]
    [ "$(jq '.packages | length' ${gallery}/projection.json)" -eq 11 ]
    [ "$(jq '[.packages[].skills // [] | length] | add' ${gallery}/projection.json)" -eq 7 ]
    jq -e '
      [.packages[].name] == [
        "pi-hashline-edit-pro",
        "pi-web-access",
        "pi-lens",
        "@dietrichgebert/ponytail",
        "@quintinshaw/pi-dynamic-workflows",
        "pi-agent-browser-native",
        "pi-lean-ctx",
        "pi-btw",
        "@jakeryderv/pi-artifacts",
        "@ygncode/pi-insights",
        "pi-subagentura"
      ]
      and (.packages[] | select(.name == "@dietrichgebert/ponytail") | .skills == [])
    ' ${gallery}/projection.json >/dev/null || fail "projection manifest differs"
    grep -F 'PI_WEB_ACCESS_PROVIDER = "perplexity"' ${gallery}/index.ts >/dev/null
    grep -F 'PI_LENS_DISABLE_LSP_INSTALL = "1"' ${gallery}/index.ts >/dev/null
    grep -F 'LEAN_CTX_BIN' ${gallery}/index.ts >/dev/null

    smoke="$TMPDIR/pi-gallery-smoke"
    mkdir -p "$smoke/home" "$smoke/agent" "$smoke/project" "$smoke/sentinels"
    printf '%s\n' '{"name":"lens-language-gate","private":true}' > "$smoke/project/package.json"
    printf '%s\n' 'const answer: number = 42;' > "$smoke/project/probe.ts"
    printf '%s\n' 'answer: int = 42' > "$smoke/project/probe.py"
    printf '%s\n' '{"type":"get_commands"}' > "$smoke/input.jsonl"
    for command in npm npx pip pip3 curl wget bun pnpm yarn; do
      cat > "$smoke/sentinels/$command" <<'SH'
    #!/bin/sh
    printf '%s\n' "$0 $*" >> "$PI_GALLERY_INSTALLER_SENTINEL"
    exit 97
    SH
      chmod +x "$smoke/sentinels/$command"
    done
    (
      cd "$smoke/project"
      HOME="$smoke/home" \
      PI_CODING_AGENT_DIR="$smoke/agent" \
      PI_GALLERY_INSTALLER_SENTINEL="$smoke/installer-invocations" \
      PI_OFFLINE=1 \
      PATH="$smoke/sentinels":${
        lib.makeBinPath [
          piPackages.agent-browser
          piPackages.lean-ctx
        ]
      }:$PATH \
        ${coreutils}/bin/timeout 120 \
        ${lib.getExe piPackage} \
        --mode rpc --no-session --offline \
        --no-extensions --no-skills --no-prompt-templates \
        --no-context-files --no-approve \
        --extension ${gallery}/index.ts <"$smoke/input.jsonl" >"$smoke/output.log" 2>&1
    ) || {
      cat "$smoke/output.log" >&2
      fail "aggregate Pi gallery failed to load"
    }
    jq -s -e '
      any(
        .[];
        .type == "response"
        and .command == "get_commands"
        and .success == true
        and ([.data.commands[].name] as $names
          | ([
              "artifacts-clean",
              "btw",
              "btw:tangent",
              "cancel-all-flows",
              "insights",
              "viewer",
              "workflow",
              "workflows"
            ] - $names | length) == 0)
      )
    ' "$smoke/output.log" >/dev/null || {
      cat "$smoke/output.log" >&2
      fail "new Pi gallery commands were not registered"
    }
    [ ! -e "$smoke/agent/settings.json" ] || fail "gallery wrote Pi settings"
    [ ! -e "$smoke/home/.npm" ] || fail "gallery invoked npm"
    [ ! -e "$smoke/installer-invocations" ] || {
      cat "$smoke/installer-invocations" >&2
      fail "Lens invoked a runtime installer or downloader"
    }
    [ ! -e "$smoke/home/.pi-lens/bin" ] || fail "Lens populated its managed binary directory"
    [ ! -e "$smoke/home/.pi-lens/tools" ] || fail "Lens populated its managed tool directory"

    quiet_smoke="$TMPDIR/pi-quiet-renderer-smoke"
    mkdir -p "$quiet_smoke/home" "$quiet_smoke/agent"
    printf '%s\n' '{"type":"get_commands"}' | (
      cd "$quiet_smoke/home"
      HOME="$quiet_smoke/home" \
      PI_CODING_AGENT_DIR="$quiet_smoke/agent" \
      PI_OFFLINE=1 \
        ${coreutils}/bin/timeout 60 \
        ${lib.getExe piPackage} \
        --mode rpc --no-session --offline \
        --no-extensions --no-skills --no-prompt-templates \
        --no-context-files --no-approve \
        --extension ${quiet}
    ) >"$quiet_smoke/output.jsonl" 2>"$quiet_smoke/error.log" || {
      cat "$quiet_smoke/error.log" >&2
      fail "pi-quiet renderer seam smoke failed"
    }
    jq -s -e '
      any(
        .[];
        .type == "response"
        and .command == "get_commands"
        and .success == true
        and any(.data.commands[]; .name == "quiet" and (.description | contains("built-in + Foreign Tools")))
      )
    ' "$quiet_smoke/output.jsonl" >/dev/null || {
      cat "$quiet_smoke/output.jsonl" >&2
      fail "pi-quiet did not select the one-argument renderer seam"
    }

    touch "$out"
  ''
