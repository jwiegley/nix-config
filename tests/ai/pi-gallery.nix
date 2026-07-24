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
    litellm = root piPackages.pi-provider-litellm "pi-provider-litellm";
    router = root piPackages.pi-model-router "pi-model-router";
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
    expect_version ${roots.litellm}/package.json 2.0.0
    expect_version ${roots.router}/package.json 0.4.4
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

    [ -f ${roots.litellm}/dist/index.js ]
    [ ! -e ${roots.litellm}/node_modules ]
    grep -F 'settings?.skills?.enabled === true' ${roots.litellm}/dist/index.js >/dev/null \
      || fail "LiteLLM Skills Gateway is not explicit opt-in"
    grep -F 'settings?.mcp?.enabled === true' ${roots.litellm}/dist/index.js >/dev/null \
      || fail "LiteLLM MCP discovery is not explicit opt-in"
    ! grep -R -F '@earendil-works/pi-ai/api/' ${roots.litellm}/dist >/dev/null \
      || fail "LiteLLM provider retains Pi peer subpath imports"
    grep -F 'openAIResponsesApi } from "@earendil-works/pi-ai"' \
      ${roots.litellm}/dist/provider.js >/dev/null \
      || fail "LiteLLM provider does not use Pi's extension-safe root export"
    [ -f ${roots.router}/extensions/index.ts ]
    [ -f ${roots.router}/extensions/routing.ts ]
    [ ! -e ${roots.router}/node_modules ]

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
    [ "$(jq '.packages | length' ${gallery}/projection.json)" -eq 13 ]
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
        "pi-subagentura",
        "pi-provider-litellm",
        "@yeliu84/pi-model-router"
      ]
      and (.packages[] | select(.name == "@dietrichgebert/ponytail") | .skills == [])
    ' ${gallery}/projection.json >/dev/null || fail "projection manifest differs"
    grep -F 'PI_WEB_ACCESS_PROVIDER = "perplexity"' ${gallery}/index.ts >/dev/null
    grep -F 'PI_LENS_DISABLE_LSP_INSTALL = "1"' ${gallery}/index.ts >/dev/null
    grep -F 'LEAN_CTX_BIN' ${gallery}/index.ts >/dev/null
    grep -F 'pi-provider-litellm' ${gallery}/index.ts >/dev/null
    grep -F 'pi-model-router' ${gallery}/index.ts >/dev/null

    provider_smoke="$TMPDIR/pi-provider-router-smoke"
    mkdir -p "$provider_smoke/home" "$provider_smoke/agent" "$provider_smoke/project"
    cat > "$provider_smoke/key-helper" <<'SH'
    #!/bin/sh
    test "$#" -eq 0
    : > "$PI_LITELLM_HELPER_MARKER"
    printf '%s\n' synthetic-key
    SH
    chmod +x "$provider_smoke/key-helper"
    cat > "$provider_smoke/agent/models.json" <<JSON
    {
      "providers": {
        "litellm": {
          "baseUrl": "https://litellm.invalid/v1",
          "apiKey": "!$provider_smoke/key-helper",
          "models": [{
            "id": "positron_openai/gpt-5.6-sol",
            "name": "GPT 5.6 Sol",
            "api": "openai-responses",
            "reasoning": true,
            "input": ["text", "image"],
            "contextWindow": 1050000,
            "maxTokens": 128000,
            "cost": {"input": 5, "output": 30, "cacheRead": 0.5, "cacheWrite": 6.25}
          }]
        },
        "router": {
          "baseUrl": "router://local",
          "apiKey": "pi-model-router",
          "api": "router-local-api",
          "models": [{
            "id": "sol",
            "name": "Router sol",
            "reasoning": true,
            "input": ["text", "image"],
            "contextWindow": 1050000,
            "maxTokens": 128000,
            "cost": {"input": 0, "output": 0, "cacheRead": 0, "cacheWrite": 0},
            "thinkingLevelMap": {"xhigh": "xhigh"}
          }]
        }
      }
    }
    JSON
    cat > "$provider_smoke/agent/models-store.json" <<JSON
    {
      "litellm": {
        "checkedAt": $(date +%s)000,
        "models": [{
          "id": "native-provider-proof",
          "name": "Native provider proof",
          "provider": "litellm",
          "api": "openai-completions",
          "baseUrl": "https://litellm.invalid/v1",
          "reasoning": false,
          "input": ["text"],
          "contextWindow": 128000,
          "maxTokens": 4096,
          "cost": {"input": 0, "output": 0, "cacheRead": 0, "cacheWrite": 0}
        }]
      }
    }
    JSON
    cat > "$provider_smoke/agent/model-router.json" <<'JSON'
    {
      "debug": false,
      "phaseBias": 0.5,
      "models": {
        "sol": {
          "model": "litellm/positron_openai/gpt-5.6-sol",
          "contextWindow": 1050000,
          "maxTokens": 128000,
          "reasoning": true,
          "thinkingLevels": ["low", "medium", "high", "xhigh"]
        }
      },
      "profiles": {
        "sol": {
          "high": {"model": "sol", "thinking": "xhigh"},
          "medium": {"model": "sol", "thinking": "medium"},
          "low": {"model": "sol", "thinking": "low"}
        }
      }
    }
    JSON
    (
      cd "$provider_smoke/project"
      env -u LITELLM_API_KEY -u LITELLM_API_KEY_HELPER \
      HOME="$provider_smoke/home" \
      PI_CODING_AGENT_DIR="$provider_smoke/agent" \
      PI_LITELLM_HELPER_MARKER="$provider_smoke/list-helper-invoked" \
      PI_OFFLINE=1 \
      ${coreutils}/bin/timeout 60 \
        ${lib.getExe piPackage} \
        --offline --no-session --no-context-files \
        --no-extensions --no-skills --no-prompt-templates \
        --extension ${gallery}/index.ts --list-models \
        >"$provider_smoke/models.log" 2>"$provider_smoke/error.log"
    ) || {
      cat "$provider_smoke/models.log" >&2
      cat "$provider_smoke/error.log" >&2
      fail "LiteLLM provider/router model listing failed"
    }
    grep -F 'litellm' "$provider_smoke/models.log" | \
      grep -F 'positron_openai/gpt-5.6-sol' >/dev/null \
      || fail "native LiteLLM provider did not expose positron_openai/gpt-5.6-sol"
    grep -F 'litellm' "$provider_smoke/models.log" | \
      grep -F 'native-provider-proof' >/dev/null \
      || fail "LiteLLM native provider did not load its cached dynamic catalog"
    grep -F 'router' "$provider_smoke/models.log" | grep -F 'sol' >/dev/null \
      || fail "model router did not expose router/sol"

    cat > "$provider_smoke/auth-probe.ts" <<'TS'
    import { writeFileSync } from "node:fs";

    export default function authProbe(pi: any) {
      pi.on("session_start", async (_event: unknown, ctx: any) => {
        const result = await ctx.modelRegistry.getProviderAuth("litellm");
        if (result?.auth?.apiKey !== "synthetic-key") {
          throw new Error("LiteLLM command credential did not resolve");
        }
        writeFileSync(process.env.PI_LITELLM_AUTH_MARKER!, "ok\n");
      });
    }
    TS
    rm -f "$provider_smoke/auth-helper-invoked" "$provider_smoke/auth-ok"
    printf '%s\n' '{"type":"get_commands"}' | (
      cd "$provider_smoke/project"
      env -u LITELLM_API_KEY -u LITELLM_API_KEY_HELPER \
      HOME="$provider_smoke/home" \
      PI_CODING_AGENT_DIR="$provider_smoke/agent" \
      PI_LITELLM_HELPER_MARKER="$provider_smoke/auth-helper-invoked" \
      PI_LITELLM_AUTH_MARKER="$provider_smoke/auth-ok" \
      PI_OFFLINE=1 \
        ${coreutils}/bin/timeout 60 \
        ${lib.getExe piPackage} \
        --mode rpc --offline --no-session --no-context-files \
        --no-extensions --no-skills --no-prompt-templates --no-approve \
        --extension ${gallery}/index.ts \
        --extension "$provider_smoke/auth-probe.ts"
    ) >"$provider_smoke/auth-output.log" 2>"$provider_smoke/auth-error.log" || {
      cat "$provider_smoke/auth-error.log" >&2
      fail "LiteLLM command credential probe failed"
    }
    [ -f "$provider_smoke/auth-helper-invoked" ] \
      || fail "LiteLLM command credential helper was not invoked"
    grep -Fx ok "$provider_smoke/auth-ok" >/dev/null \
      || fail "LiteLLM command credential did not reach the model registry"

    routing_smoke="$TMPDIR/pi-model-router-smoke"
    mkdir -p "$routing_smoke/home" "$routing_smoke/agent" "$routing_smoke/project"
    cat > "$routing_smoke/agent/models.json" <<'JSON'
    {
      "providers": {
        "router": {
          "api": "router-local-api",
          "apiKey": "pi-model-router",
          "baseUrl": "router://local",
          "models": [{
            "id": "sol",
            "name": "Router sol",
            "reasoning": true,
            "input": ["text"],
            "cost": {"input": 0, "output": 0, "cacheRead": 0, "cacheWrite": 0},
            "contextWindow": 128000,
            "maxTokens": 16384,
            "thinkingLevelMap": {"xhigh": "xhigh"}
          }]
        }
      }
    }
    JSON
    cat > "$routing_smoke/agent/model-router.json" <<'JSON'
    {
      "profiles": {
        "sol": {
          "high": {
            "model": "synthetic/target",
            "thinking": "xhigh",
            "thinkingLevels": ["low", "medium", "high", "xhigh"]
          },
          "medium": {
            "model": "synthetic/target",
            "thinking": "medium",
            "thinkingLevels": ["low", "medium", "high", "xhigh"]
          },
          "low": {
            "model": "synthetic/target",
            "thinking": "low",
            "thinkingLevels": ["low", "medium", "high", "xhigh"]
          }
        }
      }
    }
    JSON
    cat > "$routing_smoke/synthetic.ts" <<'TS'
    import { createAssistantMessageEventStream } from "@earendil-works/pi-ai";
    import { registerApiProvider } from "@earendil-works/pi-ai/compat";

    function syntheticStream(model: any, _context: any, options: any) {
      const stream = createAssistantMessageEventStream();
      queueMicrotask(() => {
        const text = options?.reasoning ?? "off";
        const message: any = {
          role: "assistant",
          content: [{ type: "text", text }],
          api: model.api,
          provider: model.provider,
          model: model.id,
          usage: {
            input: 0,
            output: 1,
            cacheRead: 0,
            cacheWrite: 0,
            totalTokens: 1,
            cost: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0, total: 0 },
          },
          stopReason: "stop",
          timestamp: Date.now(),
        };
        stream.push({ type: "start", partial: message });
        stream.push({ type: "text_start", contentIndex: 0, partial: message });
        stream.push({ type: "text_delta", contentIndex: 0, delta: text, partial: message });
        stream.push({ type: "text_end", contentIndex: 0, content: text, partial: message });
        stream.push({ type: "done", reason: "stop", message });
        stream.end();
      });
      return stream;
    }

    export default function synthetic(pi: any) {
      registerApiProvider({
        api: "synthetic-api",
        stream: syntheticStream,
        streamSimple: syntheticStream,
      });
      pi.registerProvider("synthetic", {
        baseUrl: "synthetic://local",
        apiKey: "synthetic",
        api: "synthetic-api",
        models: [{
          id: "target",
          name: "Synthetic",
          reasoning: true,
          input: ["text"],
          cost: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0 },
          contextWindow: 128000,
          maxTokens: 16384,
          thinkingLevelMap: { xhigh: "xhigh" },
        }],
      });
    }
    TS
    while IFS='|' read -r prompt expected; do
      env -u LITELLM_API_KEY -u LITELLM_API_KEY_HELPER \
      HOME="$routing_smoke/home" \
      PI_CODING_AGENT_DIR="$routing_smoke/agent" \
      PI_OFFLINE=1 \
        ${coreutils}/bin/timeout 60 \
        ${lib.getExe piPackage} \
        --print --offline --no-session --no-context-files \
        --no-extensions --no-skills --no-prompt-templates --no-approve \
        --extension ${gallery}/index.ts \
        --extension "$routing_smoke/synthetic.ts" \
        --provider router --model sol "$prompt" \
        </dev/null >"$routing_smoke/output" 2>"$routing_smoke/error" || {
          cat "$routing_smoke/error" >&2
          fail "model router failed for expected $expected tier"
        }
      [ "$(cat "$routing_smoke/output")" = "$expected" ] || {
        cat "$routing_smoke/output" >&2
        cat "$routing_smoke/error" >&2
        fail "model router did not select expected $expected reasoning tier"
      }
    done <<'CASES'
    briefly answer|low
    implement the change|medium
    think deeply about this architecture|xhigh
    CASES

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
              "router",
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
