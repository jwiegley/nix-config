{
  bun,
  coreutils,
  fetchurl,
  jq,
  lib,
  nodejs_22,
  piPackage,
  piPackages,
  runCommand,
  sourceForChecks,
  upstreamPiPackage,
}:

let
  root = package: name: "${package}/share/pi-packages/${name}";
  canonicalPiPackage = piPackages.pi;
  manifest = piPackages.pi-gallery.manifest;
  catalogSourceIds = builtins.attrNames manifest.sourceCatalog;
  declaredSourceIds =
    map (record: record.sourceName) (builtins.attrValues (manifest.members // manifest.supportSources))
    ++ builtins.attrNames manifest.externalSourceConsumers;
  sourceCatalogComplete = lib.sort builtins.lessThan declaredSourceIds == catalogSourceIds;
  orphanedCatalogRejected =
    lib.sort builtins.lessThan declaredSourceIds
    != builtins.attrNames (manifest.sourceCatalog // { synthetic-orphan = { }; });
  roots = lib.mapAttrs (_: member: root member.package member.attrName) manifest.members;
  manifestPackagesMatch = builtins.all (
    id:
    let
      member = manifest.members.${id};
    in
    piPackages.${member.attrName} == member.package && member.package.version == member.version
  ) manifest.order;
  gallery = "${piPackages.pi-gallery}/share/pi-gallery";
  quiet = "${piPackages.agent-resources}/share/agent-resources/pi-extensions/pi-quiet/src/index.ts";
  packageRoots = lib.escapeShellArgs (builtins.attrValues roots);
  skillPackageRoots = packageRoots;
  memberVersionChecks = lib.concatMapStringsSep "\n" (
    id: "expect_version ${roots.${id}}/package.json ${manifest.members.${id}.version}"
  ) manifest.order;
  supportVersionChecks =
    lib.concatMapStringsSep "\n"
      (
        id:
        "expect_version ${
          root manifest.supportSources.${id}.package manifest.supportSources.${id}.attrName
        }/package.json ${manifest.supportSources.${id}.version}"
      )
      (
        builtins.attrNames (
          builtins.removeAttrs manifest.supportSources [
            "agent-browser"
            "cymbal"
            "rtk"
          ]
        )
      );
  normalizationPolicy = builtins.fromJSON (
    builtins.readFile ../../packages/pi-gallery/normalization-policy.json
  );
  normalizationTargets = builtins.attrNames normalizationPolicy.targets;
  normalizationMemberFor =
    target:
    let
      matches = lib.filter (id: manifest.members.${id}.attrName == target) manifest.order;
    in
    assert builtins.length matches == 1;
    manifest.members.${builtins.head matches};
  normalizationParityChecks = lib.concatMapStringsSep "\n" (
    target:
    let
      member = normalizationMemberFor target;
      rawTarball = fetchurl member.source.args;
    in
    ''
      normalization_dir="$TMPDIR/pi-normalization/${target}"
      mkdir -p "$normalization_dir/raw"
      tar -xzf ${rawTarball} -C "$normalization_dir/raw"
      ${jq}/bin/jq \
        --arg target ${lib.escapeShellArg target} \
        --arg expectedName ${lib.escapeShellArg member.update.package} \
        --arg expectedVersion ${lib.escapeShellArg member.version} \
        --slurpfile policy ${../../packages/pi-gallery/normalization-policy.json} \
        -f ${../../packages/pi-gallery/normalize-manifest.jq} \
        "$normalization_dir/raw/package/package.json" \
        > "$normalization_dir/updater-package.json"
      cmp -s \
        "$normalization_dir/updater-package.json" \
        ${member.package.src}/package.json \
        || fail "shared normalizer drifted for ${target}"
    ''
  ) normalizationTargets;
  expectedPublicNames = map (id: manifest.members.${id}.publicName) manifest.order;
  expectedSkillCount = builtins.length (
    lib.concatMap (id: manifest.members.${id}.skills or [ ]) manifest.order
  );
  expectedPromptCount = builtins.length (
    lib.concatMap (id: manifest.members.${id}.prompts or [ ]) manifest.order
  );
in
assert builtins.length (builtins.attrNames manifest.members) == builtins.length manifest.order;
assert sourceCatalogComplete;
assert orphanedCatalogRejected;
assert manifestPackagesMatch;
assert piPackage.drvPath == canonicalPiPackage.drvPath;
assert piPackage.outPath == canonicalPiPackage.outPath;
assert (piPackage.src or null) == (upstreamPiPackage.src or null);
assert (piPackage.toolRendererWrapperAbi or null) == 1;
runCommand "pi-gallery-check"
  {
    __darwinAllowLocalNetworking = true;
    nativeBuildInputs = [
      bun
      coreutils
      jq
      nodejs_22
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

    (
      cd ${sourceForChecks}/test/ai/extensions/auto-compact-resume
      bun test index.test.ts
    )

    echo "Pi gallery check: member versions"
    ${memberVersionChecks}
    echo "Pi gallery check: support versions"
    ${supportVersionChecks}
    echo "Pi gallery check: normalization parity"
    ${normalizationParityChecks}
    echo "Pi gallery check: packaged roots"

    for package_root in ${packageRoots}; do
      [ -f "$package_root/package.json" ] || fail "missing package manifest: $package_root"
      if [ -d "$package_root/node_modules" ]; then
        if find "$package_root/node_modules" -type d \
          \( -path '*/@earendil-works/*' -o -path '*/typebox' \) -print -quit | grep -q .; then
          fail "package bundles a Pi-provided peer runtime: $package_root"
        fi
      fi
    done

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
    [ -f ${roots.multi-pass}/extensions/multi-sub.ts ]
    [ ! -e ${roots.multi-pass}/node_modules ]
    [ -f ${roots.router}/extensions/index.ts ]
    [ -f ${roots.router}/extensions/routing.ts ]
    [ ! -e ${roots.router}/node_modules ]
    [ -f ${roots.rewind}/src/index.ts ]
    [ -f ${roots.rewind}/src/core.ts ]
    [ -f ${roots.rewind}/src/ui.ts ]
    ! grep -F 'state.checkpoints.size' ${roots.rewind}/src/ui.ts >/dev/null \
      || fail "Rewind still computes the footer checkpoint count"
    ! grep -F 'checkpoint count' ${roots.rewind}/src/ui.ts >/dev/null \
      || fail "Rewind still describes a footer checkpoint count"
    [ ! -e ${roots.rewind}/node_modules ]
    [ -f ${roots.scroll}/extensions/scroll.ts ]
    [ -f ${roots.scroll}/src/search.ts ]
    [ ! -e ${roots.scroll}/node_modules ]

    [ -f ${roots.hashline}/index.ts ]
    [ ! -e ${roots.hashline}/node_modules/better-sqlite3 ]
    [ -d ${roots.hashline}/node_modules/sql.js ]
    [ -d ${roots.hashline}/node_modules/xxhash-wasm ]
    grep -F 'Bun standalone aborts before the native import can fall back' \
      ${roots.hashline}/src/hash-store.ts >/dev/null

    [ -f ${roots.smart-fetch}/dist/index.js ]
    [ -d ${roots.smart-fetch}/node_modules/defuddle ]
    [ -d ${roots.smart-fetch}/node_modules/linkedom ]
    [ -d ${roots.smart-fetch}/node_modules/wreq-js ]
    [ ! -e ${roots.smart-fetch}/node_modules/@earendil-works ]
    [ ! -e ${roots.smart-fetch}/node_modules/@sinclair/typebox ]
    [ -f ${roots.smart-web-search}/index.ts ]
    [ -f ${roots.smart-web-search}/markdown.ts ]
    [ -d ${roots.smart-web-search}/node_modules/defuddle ]
    [ -d ${roots.smart-web-search}/node_modules/linkedom ]
    [ -d ${roots.smart-web-search}/node_modules/wreq-js ]

    [ -f ${roots.lens}/dist/index.js ]
    ! grep -R -F 'autoInstall: true' ${roots.lens}/dist/clients >/dev/null \
      || fail "Lens still enables an auto-installer"
    grep -F 'disabled by Nix policy' ${roots.lens}/dist/clients/installer/index.js >/dev/null \
      || fail "Lens installer policy patch is missing"
    ! grep -R -E '"npx(\.cmd)?"' ${roots.lens}/dist >/dev/null \
      || fail "Lens still contains a live npx fallback"
    grep -F 'setStatus("pi-lens-lsp", activeIds.length > 0 ? theme.bold("LSP") : theme.fg("dim", "LSP"));' \
      ${roots.lens}/dist/index.js >/dev/null \
      || fail "Lens footer status is not compact"


    [ -f ${roots.ponytail}/pi-extension/index.js ]

    [ -f ${roots.browser}/dist/extensions/agent-browser/index.js ]
    [ -f ${roots.blackhole}/index.ts ]
    [ ! -e ${roots.blackhole}/node_modules ]
    [ -f ${roots.caveman}/extensions/caveman.ts ]
    [ ! -e ${roots.caveman}/node_modules ]
    grep -F 'ctx.ui.setStatus("caveman", undefined);' \
      ${roots.caveman}/extensions/caveman.ts >/dev/null \
      || fail "Caveman footer status is not disabled"
    ! grep -F 'caveman level:' ${roots.caveman}/extensions/caveman.ts >/dev/null \
      || fail "Caveman footer still renders the level lighter"
    [ -f ${roots.goal}/extensions/goal.ts ]
    [ ! -e ${roots.goal}/node_modules ]
    grep -F 'return `''${prefix}: ''${statusLabel(goal)}''${usage}`;' \
      ${roots.goal}/extensions/goal-core.ts >/dev/null \
      || fail "Goal footer still repeats the objective"
    [ -f ${roots.markdown-preview}/index.ts ]
    [ -d ${roots.markdown-preview}/node_modules/puppeteer-core ]
    [ -f ${roots.rtk-optimizer}/index.ts ]
    [ ! -e ${roots.rtk-optimizer}/node_modules ]
    [ -f ${roots.cymbal-extension}/dist/index.ts ]
    [ ! -e ${roots.cymbal-extension}/node_modules ]
    [ -f ${roots.dynamic-workflows}/extensions/workflow.ts ]
    [ -d ${roots.dynamic-workflows}/node_modules/acorn ]
    [ -f ${roots.dynamic-workflows}/skills/workflow-authoring/SKILL.md ]
    [ -f ${roots.dynamic-workflows}/skills/workflow-patterns/SKILL.md ]
    [ -f ${roots.subagents}/index.ts ]
    [ -d ${roots.subagents}/node_modules/jiti ]
    [ -d ${roots.subagents}/node_modules/yaml ]
    [ ! -e ${roots.subagents}/node_modules/typebox ]
    [ -f ${roots.subagents}/skills/pi-subagents/SKILL.md ]
    cymbal_version=$(${lib.getExe piPackages.cymbal} --version)
    printf '%s\n' "$cymbal_version" | grep -F '${manifest.supportSources.cymbal.version}' >/dev/null \
      || fail "Cymbal version drifted: $cymbal_version"

    rtk_version=$(${lib.getExe piPackages.rtk} --version)
    printf '%s\n' "$rtk_version" | grep -F '${manifest.supportSources.rtk.version}' >/dev/null \
      || fail "RTK version drifted: $rtk_version"


    browser_version=$(${lib.getExe piPackages.agent-browser} --version)
    printf '%s\n' "$browser_version" | grep -F '${manifest.supportSources.agent-browser.version}' >/dev/null \
      || fail "agent-browser version drifted: $browser_version"

    [ -f ${gallery}/index.ts ]
    [ -f ${gallery}/projection.json ]
    [ "$(jq '.packages | length' ${gallery}/projection.json)" -eq ${toString (builtins.length manifest.order)} ]
    [ "$(jq '[.packages[].skills // [] | length] | add' ${gallery}/projection.json)" -eq ${toString expectedSkillCount} ]
    [ "$(jq '[.packages[].prompts // [] | length] | add' ${gallery}/projection.json)" -eq ${toString expectedPromptCount} ]
    jq --argjson expected '${builtins.toJSON expectedPublicNames}' -e '
      [.packages[].name] == $expected
      and (.packages[] | select(.name == "@dietrichgebert/ponytail") | .skills == [])
    ' ${gallery}/projection.json >/dev/null || fail "projection manifest differs"
    grep -F 'PONYTAIL_HIDE_STATUS = "1"' ${gallery}/index.ts >/dev/null
    grep -F 'PI_LENS_DISABLE_LSP_INSTALL = "1"' ${gallery}/index.ts >/dev/null
    grep -F 'pi-model-router' ${gallery}/index.ts >/dev/null

    provider_smoke="$TMPDIR/pi-provider-router-smoke"
    mkdir -p "$provider_smoke/home" "$provider_smoke/agent" "$provider_smoke/project"
    cat > "$provider_smoke/key-helper" <<'SH'
    #!/bin/sh
    test "$#" -eq 0
    : > "$PI_LOCAL_MODEL_HELPER_MARKER"
    printf '%s\n' synthetic-key
    SH
    chmod +x "$provider_smoke/key-helper"
    cat > "$provider_smoke/agent/models.json" <<JSON
    {
      "providers": {
        "omlx": {
          "api": "openai-completions",
          "baseUrl": "http://localhost:8000/v1",
          "apiKey": "!$provider_smoke/key-helper",
          "models": [{
            "id": "Qwen3.6-27B-oQ4e-mtp",
            "name": "Qwen3.6 27B",
            "reasoning": true,
            "input": ["text"],
            "contextWindow": 262144,
            "maxTokens": 65536,
            "cost": {"input": 0, "output": 0, "cacheRead": 0, "cacheWrite": 0}
          }]
        },
        "llama-cpp-local": {
          "api": "openai-completions",
          "baseUrl": "http://localhost:8080/v1",
          "apiKey": "not-needed",
          "models": [{
            "id": "GLM-5.2",
            "name": "GLM 5.2",
            "reasoning": true,
            "input": ["text"],
            "contextWindow": 202752,
            "maxTokens": 65536,
            "cost": {"input": 0, "output": 0, "cacheRead": 0, "cacheWrite": 0}
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
            "input": ["text"],
            "contextWindow": 262144,
            "maxTokens": 65536,
            "cost": {"input": 0, "output": 0, "cacheRead": 0, "cacheWrite": 0},
            "thinkingLevelMap": {"xhigh": "xhigh"}
          }]
        }
      }
    }
    JSON
    catalog_timestamp=$(date +%s)000
    cat > "$provider_smoke/agent/models-store.json" <<JSON
    {
      "omlx": {
        "checkedAt": $catalog_timestamp,
        "lastModified": $catalog_timestamp,
        "models": [{
          "id": "native-provider-proof",
          "name": "Native provider proof",
          "provider": "omlx",
          "api": "openai-completions",
          "baseUrl": "http://localhost:8000/v1",
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
          "model": "omlx/Qwen3.6-27B-oQ4e-mtp",
          "contextWindow": 262144,
          "maxTokens": 65536,
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
      env -u OMLX_API_KEY -u LLAMA_SWAP_API_KEY \
      HOME="$provider_smoke/home" \
      PI_CODING_AGENT_DIR="$provider_smoke/agent" \
      PI_LOCAL_MODEL_HELPER_MARKER="$provider_smoke/list-helper-invoked" \
      PI_OFFLINE=1 \
      ${coreutils}/bin/timeout 120 \
        ${lib.getExe piPackage} \
        --offline --no-session --no-context-files \
        --no-extensions --no-skills --no-prompt-templates \
        --extension ${gallery}/index.ts --list-models \
        >"$provider_smoke/models.log" 2>"$provider_smoke/error.log"
    ) || {
      cat "$provider_smoke/models.log" >&2
      cat "$provider_smoke/error.log" >&2
      fail "local provider/router model listing failed"
    }
    grep -F 'omlx' "$provider_smoke/models.log" | \
      grep -F 'Qwen3.6-27B-oQ4e-mtp' >/dev/null \
      || fail "oMLX provider did not expose Qwen3.6-27B-oQ4e-mtp"
    grep -F 'llama-cpp-local' "$provider_smoke/models.log" | \
      grep -F 'GLM-5.2' >/dev/null \
      || fail "llama-swap provider did not expose GLM-5.2"
    ! grep -F 'native-provider-proof' "$provider_smoke/models.log" >/dev/null \
      || fail "local provider loaded its disabled dynamic catalog"
    grep -F 'router' "$provider_smoke/models.log" | grep -F 'sol' >/dev/null \
      || fail "model router did not expose router/sol"

    cat > "$provider_smoke/auth-probe.ts" <<'TS'
    import { writeFileSync } from "node:fs";

    export default function authProbe(pi: any) {
      pi.on("session_start", async (_event: unknown, ctx: any) => {
        const result = await ctx.modelRegistry.getProviderAuth("omlx");
        if (result?.auth?.apiKey !== "synthetic-key") {
          throw new Error("oMLX command credential did not resolve");
        }
        writeFileSync(process.env.PI_LOCAL_MODEL_AUTH_MARKER!, "ok\n");
      });
    }
    TS
    rm -f "$provider_smoke/auth-helper-invoked" "$provider_smoke/auth-ok"
    printf '%s\n' '{"type":"get_commands"}' | (
      cd "$provider_smoke/project"
      env -u OMLX_API_KEY -u LLAMA_SWAP_API_KEY \
      HOME="$provider_smoke/home" \
      PI_CODING_AGENT_DIR="$provider_smoke/agent" \
      PI_LOCAL_MODEL_HELPER_MARKER="$provider_smoke/auth-helper-invoked" \
      PI_LOCAL_MODEL_AUTH_MARKER="$provider_smoke/auth-ok" \
      PI_OFFLINE=1 \
        ${coreutils}/bin/timeout 60 \
        ${lib.getExe piPackage} \
        --mode rpc --offline --no-session --no-context-files \
        --no-extensions --no-skills --no-prompt-templates --no-approve \
        --extension ${gallery}/index.ts \
        --extension "$provider_smoke/auth-probe.ts"
    ) >"$provider_smoke/auth-output.log" 2>"$provider_smoke/auth-error.log" || {
      cat "$provider_smoke/auth-error.log" >&2
      fail "oMLX command credential probe failed"
    }
    [ -f "$provider_smoke/auth-helper-invoked" ] \
      || fail "oMLX command credential helper was not invoked"
    grep -Fx ok "$provider_smoke/auth-ok" >/dev/null \
      || fail "oMLX command credential did not reach the model registry"

    routing_smoke="$TMPDIR/pi-model-router-smoke"
    mkdir -p "$routing_smoke/home" "$routing_smoke/agent" "$routing_smoke/project"
    cat > "$routing_smoke/local-server.mjs" <<'JS'
    import { appendFileSync, writeFileSync } from "node:fs";
    import { createServer } from "node:http";

    const server = createServer((request, response) => {
      let body = "";
      request.setEncoding("utf8");
      request.on("data", chunk => { body += chunk; });
      request.on("end", () => {
        appendFileSync(process.env.PI_LOCAL_MODELS_MARKER, JSON.parse(body).model + "\n");
        response.writeHead(200, { "content-type": "text/event-stream" });
        response.write('data: {"id":"proof","object":"chat.completion.chunk","created":1,"model":"local-proof","choices":[{"index":0,"delta":{"role":"assistant","content":"ok"},"finish_reason":null}]}\n\n');
        response.write('data: {"id":"proof","object":"chat.completion.chunk","created":1,"model":"local-proof","choices":[{"index":0,"delta":{},"finish_reason":"stop"}]}\n\n');
        response.end("data: [DONE]\n\n");
      });
    });
    server.listen(0, "127.0.0.1", () => {
      writeFileSync(process.env.PI_LOCAL_PORT_FILE, String(server.address().port));
    });
    JS
    PI_LOCAL_PORT_FILE="$routing_smoke/port" \
    PI_LOCAL_MODELS_MARKER="$routing_smoke/models-seen" \
      node "$routing_smoke/local-server.mjs" &
    local_server_pid=$!
    trap 'kill "$local_server_pid" 2>/dev/null || true' EXIT
    for _ in $(seq 1 100); do
      [ -s "$routing_smoke/port" ] && break
      sleep 0.05
    done
    [ -s "$routing_smoke/port" ] || fail "local provider request oracle did not start"
    local_port=$(cat "$routing_smoke/port")

    cat > "$routing_smoke/agent/models.json" <<JSON
    {
      "providers": {
        "omlx": {
          "api": "openai-completions",
          "apiKey": "dummy-key",
          "baseUrl": "http://127.0.0.1:$local_port/v1",
          "models": [{
            "id": "Qwen3.6-27B-oQ4e-mtp",
            "name": "Qwen3.6 27B",
            "reasoning": true,
            "input": ["text"],
            "cost": {"input": 0, "output": 0, "cacheRead": 0, "cacheWrite": 0},
            "contextWindow": 262144,
            "maxTokens": 65536
          }]
        },
        "llama-cpp-local": {
          "api": "openai-completions",
          "apiKey": "not-needed",
          "baseUrl": "http://127.0.0.1:$local_port/v1",
          "models": [{
            "id": "GLM-5.2",
            "name": "GLM 5.2",
            "reasoning": true,
            "input": ["text"],
            "cost": {"input": 0, "output": 0, "cacheRead": 0, "cacheWrite": 0},
            "contextWindow": 202752,
            "maxTokens": 65536
          }]
        },
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
    while IFS='|' read -r provider model; do
      env -u OMLX_API_KEY -u LLAMA_SWAP_API_KEY \
      HOME="$routing_smoke/home" \
      PI_CODING_AGENT_DIR="$routing_smoke/agent" \
      PI_OFFLINE=1 \
        ${coreutils}/bin/timeout 60 \
        ${lib.getExe piPackage} \
        --print --offline --no-session --no-context-files \
        --no-extensions --no-skills --no-prompt-templates --no-approve \
        --extension ${gallery}/index.ts \
        --provider "$provider" --model "$model" "verify direct provider" \
        </dev/null >"$routing_smoke/$provider-output" 2>"$routing_smoke/$provider-error" || {
          cat "$routing_smoke/$provider-error" >&2
          fail "$provider request smoke failed"
        }
    done <<'PROVIDERS'
    omlx|Qwen3.6-27B-oQ4e-mtp
    llama-cpp-local|GLM-5.2
    PROVIDERS
    grep -Fx Qwen3.6-27B-oQ4e-mtp "$routing_smoke/models-seen" >/dev/null \
      || fail "oMLX request did not reach its direct provider"
    grep -Fx GLM-5.2 "$routing_smoke/models-seen" >/dev/null \
      || fail "llama-swap request did not reach its direct provider"

    while IFS='|' read -r prompt expected; do
      env -u OMLX_API_KEY -u LLAMA_SWAP_API_KEY \
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
          status=$?
          cat "$routing_smoke/error" >&2
          fail "model router failed for expected $expected tier with status $status"
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
    printf '%s\n' \
      '{"id":"commands","type":"get_commands"}' \
      '{"id":"ponytail","type":"prompt","message":"/ponytail ultra"}' \
      '{"id":"entries","type":"get_entries"}' > "$smoke/input.jsonl"
    for command in npm npx pip pip3 curl wget bun pnpm yarn; do
      cat > "$smoke/sentinels/$command" <<'SH'
    #!/bin/sh
    printf '%s\n' "$0 $*" >> "$PI_GALLERY_INSTALLER_SENTINEL"
    exit 97
    SH
      chmod +x "$smoke/sentinels/$command"
    done
    for package_root in ${skillPackageRoots}; do
      [ ! -d "$package_root/skills" ] \
        || find "$package_root/skills" -type f -name SKILL.md -print
    done | sort -u > "$smoke/expected-skills"
    jq -Rsc '[splits("\n") | select(length > 0) | sub("/SKILL.md$"; "")]' \
      "$smoke/expected-skills" > "$smoke/skill-paths.json"
    cat > "$smoke/all-skills.ts" <<EOF
    const skillPaths: string[] = $(cat "$smoke/skill-paths.json");
    export default function register(pi: any) {
      pi.on("resources_discover", () => ({ skillPaths }));
    }
    EOF
    cat > "$smoke/active-tools.ts" <<'EOF'
    import { writeFileSync } from "node:fs";
    export default function activeTools(pi: any) {
      pi.on("session_start", () => {
        writeFileSync(process.env.PI_GALLERY_ACTIVE_TOOLS!, JSON.stringify(pi.getActiveTools().sort()));
      });
    }
    EOF
    (
      cd "$smoke/project"
      HOME="$smoke/home" \
      PI_CODING_AGENT_DIR="$smoke/agent" \
      PI_GALLERY_ACTIVE_TOOLS="$smoke/active-tools.json" \
      PI_GALLERY_TOOL_OWNERS_FILE="$smoke/tool-owners.json" \
      PI_GALLERY_INSTALLER_SENTINEL="$smoke/installer-invocations" \
      PI_OFFLINE=1 \
      PATH="$smoke/sentinels":${
        lib.makeBinPath [
          piPackages.agent-browser
          piPackages.cymbal
          piPackages.rtk
        ]
      }:$PATH \
        ${coreutils}/bin/timeout 120 \
        ${lib.getExe piPackage} \
        --mode rpc --no-session --offline \
        --no-extensions --no-prompt-templates \
        --no-context-files --no-approve \
        --extension ${gallery}/index.ts \
        --extension "$smoke/all-skills.ts" \
        --extension "$smoke/active-tools.ts" \
        <"$smoke/input.jsonl" >"$smoke/output.log" 2>"$smoke/error.log"
    ) || {
      cat "$smoke/output.log" >&2
      cat "$smoke/error.log" >&2
      fail "aggregate Pi gallery failed to load"
    }
    jq -s -e '
      any(
        .[];
        .type == "response"
        and .command == "get_commands"
        and .success == true
        and ([
          "artifacts-clean",
          "blackhole",
          "blackhole-memory",
          "blackhole-recall",
          "btw",
          "btw:tangent",
          "caveman",
          "chain",
          "cymbal:remind",
          "gather-context-and-clarify",
          "goal",
          "goal-abort",
          "goal-clear",
          "goal-focus",
          "goal-list",
          "goal-pause",
          "goal-resume",
          "goal-settings",
          "goal-status",
          "goal-tweak",
          "goals",
          "goals-set",
          "sisyphus",
          "sisyphus-set",
          "insights",
          "mp-preset",
          "pool",
          "subs",
          "parallel",
          "parallel-cleanup",
          "parallel-context-build",
          "parallel-handoff-plan",
          "parallel-research",
          "parallel-review",
          "ponytail",
          "preview",
          "preview-browser",
          "preview-clear-cache",
          "preview-pdf",
          "review-loop",
          "rewind",
          "router",
          "rtk",
          "run",
          "scroll",
          "subagents",
          "subagents-doctor",
          "subagents-fleet",
          "subagents-models",
          "subagents-watchdog",
          "viewer",
          "workflows"
        ] - [.data.commands[].name] | length) == 0
        and ([.data.commands[].name | select(startswith("sidebar"))] | length) == 0
      )
    ' "$smoke/output.log" >/dev/null || {
      cat "$smoke/output.log" >&2
      fail "new Pi gallery commands were not registered"
    }
    jq -e '
      . as $actual
      | ($actual | length) == ($actual | unique | length)
        and all(
          ["batch_web_fetch", "edit", "read", "web_fetch", "web_search", "write"][];
          . as $required | $actual | index($required) != null
        )
        and all($actual[]; contains("anvil") | not)
    ' "$smoke/active-tools.json" >/dev/null || {
      cat "$smoke/active-tools.json" >&2
      fail "Pi gallery required tools, uniqueness, or retired-tool invariant failed"
    }
    validate_web_tool_owners() {
      jq -e '
        .batch_web_fetch == ["smart-fetch"]
        and .web_fetch == ["smart-fetch"]
        and .web_search == ["smart-web-search"]
      ' "$1" >/dev/null
    }
    validate_web_tool_owners "$smoke/tool-owners.json" || {
      cat "$smoke/tool-owners.json" >&2
      fail "Pi gallery web tools do not have exactly one declared owner"
    }
    jq '.web_search += ["smart-fetch"]' "$smoke/tool-owners.json" \
      > "$smoke/tool-owners-duplicate.json"
    if validate_web_tool_owners "$smoke/tool-owners-duplicate.json"; then
      fail "tool-ownership gate accepted a second web_search owner"
    fi
    jq '.web_fetch = ["smart-web-search"]' "$smoke/tool-owners.json" \
      > "$smoke/tool-owners-wrong.json"
    if validate_web_tool_owners "$smoke/tool-owners-wrong.json"; then
      fail "tool-ownership gate accepted the wrong web_fetch owner"
    fi
    jq -s -e '
      any(
        .[];
        .type == "entry_appended"
        and .entry.customType == "ponytail-mode"
        and .entry.data.mode == "ultra"
      )
    ' "$smoke/output.log" >/dev/null || {
      cat "$smoke/output.log" >&2
      fail "Ponytail command did not activate through the aggregate gallery"
    }
    while IFS= read -r skill; do
      jq -s -e --arg skill "$skill" '
        any(
          .[];
          .type == "response"
          and .command == "get_commands"
          and .success == true
          and any(.data.commands[]; .source == "skill" and .sourceInfo.path == $skill)
        )
      ' "$smoke/output.log" >/dev/null \
        || fail "Pi did not parse packaged skill frontmatter: $skill"
    done < "$smoke/expected-skills"
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
