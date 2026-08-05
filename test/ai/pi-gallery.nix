{
  bun,
  coreutils,
  fetchurl,
  jq,
  lib,
  nodejs_22,
  piPackage,
  piPackages,
  python3,
  runCommand,
  sourceForChecks,
  stdenv,
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
  localModelMemberIds = [
    "llama-swap-provider"
    "omlx-provider"
    "router"
  ];
  activeOrder =
    if stdenv.hostPlatform.isDarwin then
      manifest.order
    else
      lib.subtractLists localModelMemberIds manifest.order;
  quiet = "${piPackages.agent-resources}/share/agent-resources/pi-extensions/pi-quiet/src/index.ts";
  packageRoots = lib.escapeShellArgs (builtins.attrValues roots);
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
  expectedPublicNames = map (id: manifest.members.${id}.publicName) activeOrder;
  expectedSkillCount = builtins.length (
    lib.concatMap (id: manifest.members.${id}.skills or [ ]) activeOrder
  );
  expectedPromptCount = builtins.length (
    lib.concatMap (id: manifest.members.${id}.prompts or [ ]) activeOrder
  );
  routingExtension =
    if stdenv.hostPlatform.isDarwin then
      "${gallery}/index.ts"
    else
      "${roots.router}/extensions/index.ts";
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

    rpc_sequence="$TMPDIR/pi-rpc-sequence.py"
    cat > "$rpc_sequence" <<'PY'
    import json
    from pathlib import Path
    import subprocess
    import sys

    input_path, output_path, error_path, *command = sys.argv[1:]
    with (
        Path(input_path).open() as requests,
        Path(output_path).open("w") as output,
        Path(error_path).open("w") as errors,
    ):
        process = subprocess.Popen(
            command,
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=errors,
            text=True,
            bufsize=1,
        )
        assert process.stdin is not None
        assert process.stdout is not None
        try:
            for request_line in requests:
                request = json.loads(request_line)
                request_id = request["id"]
                process.stdin.write(request_line)
                process.stdin.flush()
                while True:
                    response_line = process.stdout.readline()
                    if not response_line:
                        raise RuntimeError(f"Pi exited before responding to {request_id}")
                    output.write(response_line)
                    output.flush()
                    response = json.loads(response_line)
                    if response.get("type") == "response" and response.get("id") == request_id:
                        break
            process.stdin.close()
            for response_line in process.stdout:
                output.write(response_line)
            status = process.wait(timeout=15)
        except BaseException:
            process.kill()
            process.wait()
            raise
    raise SystemExit(status)
    PY

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
    [ -f ${roots.usage}/index.ts ]
    [ ! -e ${roots.usage}/node_modules ]
    [ -f ${roots.multi-pass}/extensions/multi-sub.ts ]
    [ ! -e ${roots.multi-pass}/node_modules ]
    [ -f ${piPackages.pi-loop}/share/pi-packages/pi-loop/extensions/index.ts ]
    [ -f ${piPackages.pi-loop}/share/pi-packages/pi-loop/LICENSE ]
    [ ! -e ${piPackages.pi-loop}/share/pi-packages/pi-loop/node_modules ]
    grep -F 'entries[index]?.message ?? entries[index]' \
      ${piPackages.pi-loop}/share/pi-packages/pi-loop/extensions/index.ts >/dev/null \
      || fail "pi-loop nested session-entry compatibility patch is missing"
    ! grep -F 'if (entries[index]?.role === "assistant")' \
      ${piPackages.pi-loop}/share/pi-packages/pi-loop/extensions/index.ts >/dev/null \
      || fail "pi-loop still reads assistant role at the SessionEntry top level"
    for provider_root in ${roots.llama-swap-provider} ${roots.omlx-provider}; do
      [ -f "$provider_root/index.ts" ]
      [ -f "$provider_root/local-openai-provider.ts" ]
      [ -f "$provider_root/LICENSE" ]
      [ ! -e "$provider_root/node_modules" ]
    done
    grep -F 'http://localhost:8080/v1' ${roots.llama-swap-provider}/index.ts >/dev/null
    grep -F 'http://localhost:8000/v1' ${roots.omlx-provider}/index.ts >/dev/null
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
    [ -f ${roots.trace}/extensions/trace/index.ts ]
    [ -f ${roots.trace}/extensions/trace/trace_to_html.py ]
    [ ! -e ${roots.trace}/node_modules ]
    [ -z "$(find ${roots.trace} \( -name '*.pyc' -o -name __pycache__ \) -print -quit)" ]
    grep -F 'JSON.stringify(sanitizeTraceValue(event))' \
      ${roots.trace}/extensions/trace/index.ts >/dev/null \
      || fail "Trace does not sanitize persisted events"
    grep -F 'JSON.stringify(sanitizeTraceValue(event.result))' \
      ${roots.trace}/extensions/trace/index.ts >/dev/null \
      || fail "Trace does not sanitize tool-result previews"

    trace_runtime="$TMPDIR/pi-trace-runtime"
    mkdir -p "$trace_runtime/home/.pi/agent/sessions" "$trace_runtime/project"
    cat > "$trace_runtime/probe.ts" <<EOF
    import { readFileSync } from "node:fs";
    import trace from "${roots.trace}/extensions/trace/index.ts";

    const handlers = new Map<string, Array<(event: any, ctx?: any) => any>>();
    const commands = new Map<string, { handler: (args: string, ctx: any) => Promise<void> }>();
    const pi = {
      on(name: string, handler: (event: any, ctx?: any) => any) {
        const current = handlers.get(name) ?? [];
        current.push(handler);
        handlers.set(name, current);
      },
      registerCommand(name: string, command: any) { commands.set(name, command); },
    };
    trace(pi as any);
    const ctx = {
      cwd: process.env.TRACE_PROJECT,
      sessionManager: { getSessionFile: () => process.env.TRACE_SESSION_FILE },
      ui: { setStatus() {}, notify() {} },
    };
    const call = async (name: string, event: any = {}) => {
      for (const handler of handlers.get(name) ?? []) await handler(event, ctx);
    };

    await call("session_start", { sessionId: "runtime-session", reason: "test" });
    await call("before_agent_start", { prompt: "trace fixture", systemPrompt: "fixture" });
    await call("turn_start", { turnIndex: 0 });
    await call("before_provider_request", {
      payload: {
        model: "fixture",
        max_tokens: 42,
        apiKey: "trace-secret-sentinel",
        "x-api-key": "trace-x-api-key-sentinel",
        cookie: "trace-cookie-sentinel",
      },
    });
    await call("message_end", {
      message: {
        role: "assistant",
        content: [{ type: "text", text: "ordinary successful response" }],
        stopReason: "stop",
      },
    });
    await call("tool_execution_start", {
      toolCallId: "tool-1",
      toolName: "read",
      args: { path: "probe", authorization: "trace-secret-sentinel" },
    });
    await call("tool_execution_end", {
      toolCallId: "tool-1",
      toolName: "read",
      args: { path: "probe" },
      result: {
        apiKey: "trace-secret-sentinel",
        proxyAuthorization: "trace-proxy-auth-sentinel",
        secretAccessKey: "trace-secret-access-sentinel",
        value: "safe-result",
      },
      isError: false,
    });
    for (let i = 0; i < 2000; i++) {
      await call("model_select", {
        model: { id: "flush-model-" + i },
      });
    }
    await call("turn_end", {
      turnIndex: 0,
      message: {
        role: "assistant",
        content: [{ type: "text", text: "trace-final-flush-sentinel" }],
      },
      toolResults: [],
    });
    await commands.get("trace")?.handler("", ctx);
    const activeHtml = readFileSync(
      process.env.TRACE_PROJECT + "/../home/.pi/agent/traces/runtime-session/trace.html",
      "utf8",
    );
    if (!activeHtml.includes("trace-final-flush-sentinel")) {
      throw new Error("active /trace render omitted buffered events");
    }
    await call("session_shutdown");
    EOF
    HOME="$trace_runtime/home" \
      TRACE_PROJECT="$trace_runtime/project" \
      TRACE_SESSION_FILE="$trace_runtime/home/.pi/agent/sessions/runtime-session.jsonl" \
      ${bun}/bin/bun "$trace_runtime/probe.ts"
    trace_dir="$trace_runtime/home/.pi/agent/traces/runtime-session"
    trace_events="$trace_dir/events.jsonl"
    trace_html="$trace_dir/trace.html"
    [ -f "$trace_events" ] || fail "Trace runtime fixture did not write events.jsonl"
    [ -f "$trace_html" ] || fail "Trace runtime fixture did not render trace.html"
    [ "$(${coreutils}/bin/stat -c '%a' "$trace_dir")" = 700 ] \
      || fail "Trace session directory is not private"
    [ "$(${coreutils}/bin/stat -c '%a' "$trace_events")" = 600 ] \
      || fail "Trace events are not private"
    [ "$(${coreutils}/bin/stat -c '%a' "$trace_html")" = 600 ] \
      || fail "Rendered trace is not private"
    ! grep -F 'trace-secret-sentinel' "$trace_events" "$trace_html" >/dev/null \
      || fail "Trace persisted a secret-like value"
    for secret in \
      trace-x-api-key-sentinel \
      trace-cookie-sentinel \
      trace-proxy-auth-sentinel \
      trace-secret-access-sentinel; do
      ! grep -F "$secret" "$trace_events" "$trace_html" >/dev/null \
        || fail "Trace persisted an extended secret-like value"
    done
    grep -F 'trace-final-flush-sentinel' "$trace_events" >/dev/null \
      || fail "Trace did not flush its final event"
    grep -F 'trace-final-flush-sentinel' "$trace_html" >/dev/null \
      || fail "Trace rendered before its final event was flushed"
    ${jq}/bin/jq -s -e '
      any(
        .[];
        .type == "llm_request"
        and .input.max_tokens == 42
        and .input.apiKey == "[REDACTED]"
        and .input["x-api-key"] == "[REDACTED]"
        and .input.cookie == "[REDACTED]"
      )
      and any(
        .[];
        .type == "tool_end"
        and (.resultPreview | fromjson | .apiKey) == "[REDACTED]"
        and (.resultPreview | fromjson | .proxyAuthorization) == "[REDACTED]"
        and (.resultPreview | fromjson | .secretAccessKey) == "[REDACTED]"
      )
      and any(.[]; .type == "step_end" and (has("errorMessage") | not))
    ' "$trace_events" >/dev/null \
      || fail "Trace sanitizer changed telemetry or optional-field semantics"
    ${python3}/bin/python3 - "$trace_events" "$trace_dir" \
      ${roots.trace}/extensions/trace/trace_to_html.py <<'PY'
    import importlib.util
    import json
    from pathlib import Path
    import sys

    events_path = Path(sys.argv[1])
    session_dir = sys.argv[2]
    renderer_path = sys.argv[3]
    spec = importlib.util.spec_from_file_location("pi_trace_renderer", renderer_path)
    renderer = importlib.util.module_from_spec(spec)
    assert spec.loader is not None
    spec.loader.exec_module(renderer)
    events = [json.loads(line) for line in events_path.read_text().splitlines() if line]
    root = renderer.build_tree(events, session_dir=session_dir)

    def nodes(node):
        yield node
        for child in node.get("children", []):
            yield from nodes(child)

    steps = [node for node in nodes(root) if node.get("type") == "step"]
    if len(steps) != 1 or steps[0].get("status") != "ok":
        raise SystemExit("Trace renderer misclassified an ordinary step")
    PY

    for package_root in \
      ${roots.trace} \
      ${roots.cache-optimizer}; do
      ! grep -R -i 'litellm' "$package_root" >/dev/null \
        || fail "Pi extension package reintroduced a retired LiteLLM reference: $package_root"
    done
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
    for lens_runtime in \
      ${roots.lens}/dist/index.js \
      ${roots.lens}/dist/clients/runtime-tool-result.js
    do
      grep -F 'const rawFilePath = typeof rawPath === "string" ? rawPath : void 0;' \
        "$lens_runtime" >/dev/null \
        || fail "Lens does not ignore array-valued tool paths"
      node --check "$lens_runtime"
    done


    [ -f ${roots.ponytail}/pi-extension/index.js ]

    [ -f ${roots.browser}/dist/extensions/agent-browser/index.js ]
    [ -f ${roots.blackhole}/index.ts ]
    [ ! -e ${roots.blackhole}/node_modules ]
    ${jq}/bin/jq -e '
      .memory == true
      and .compaction == "auto"
      and .compactionEngine == "blackhole"
    ' ${roots.blackhole}/example-config.json >/dev/null \
      || fail "Blackhole does not ship memory and automatic Blackhole compaction defaults"
    [ -f ${roots.cache-optimizer}/index.ts ]
    [ ! -e ${roots.cache-optimizer}/node_modules ]
    [ "$(grep -Fc 'Nix manages models.json; edit config/ai and switch the configuration instead.' \
      ${roots.cache-optimizer}/index.ts)" -eq 2 ] \
      || fail "Cache Optimizer does not refuse both models.json write paths"
    [ -f ${roots.caveman}/extensions/caveman.ts ]
    [ ! -e ${roots.caveman}/node_modules ]
    grep -F 'ctx.ui.setStatus("caveman", undefined);' \
      ${roots.caveman}/extensions/caveman.ts >/dev/null \
      || fail "Caveman footer status is not disabled"
    ! grep -F 'caveman level:' ${roots.caveman}/extensions/caveman.ts >/dev/null \
      || fail "Caveman footer still renders the level lighter"
    [ -f ${roots.copy-message}/extensions/copy-message.ts ]
    [ ! -e ${roots.copy-message}/node_modules ]
    ! grep -F 'spawnSync' ${roots.copy-message}/extensions/copy-message.ts >/dev/null \
      || fail "Copy Message still carries a platform-specific clipboard implementation"
    grep -F 'import { copyToClipboard } from "@earendil-works/pi-coding-agent";' \
      ${roots.copy-message}/extensions/copy-message.ts >/dev/null \
      || fail "Copy Message does not use Pi's portable clipboard helper"
    (
      cd ${sourceForChecks}
      PI_COPY_MESSAGE_EXTENSION=${roots.copy-message}/extensions/copy-message.ts \
        bun test ./test/ai/pi-copy-message.check.ts
    )
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
    [ "$(jq '.packages | length' ${gallery}/projection.json)" -eq ${toString (builtins.length activeOrder)} ]
    [ "$(jq '[.packages[].skills // [] | length] | add' ${gallery}/projection.json)" -eq ${toString expectedSkillCount} ]
    [ "$(jq '[.packages[].prompts // [] | length] | add' ${gallery}/projection.json)" -eq ${toString expectedPromptCount} ]
    jq --argjson expected '${builtins.toJSON expectedPublicNames}' -e '
      [.packages[].name] == $expected
      and (.packages[] | select(.name == "@dietrichgebert/ponytail") | .skills == [])
    ' ${gallery}/projection.json >/dev/null || fail "projection manifest differs"
    grep -F 'PONYTAIL_HIDE_STATUS = "1"' ${gallery}/index.ts >/dev/null
    grep -F 'PI_LENS_DISABLE_LSP_INSTALL = "1"' ${gallery}/index.ts >/dev/null
    ${
      if stdenv.hostPlatform.isDarwin then
        ''
          grep -F 'pi-model-router' ${gallery}/index.ts >/dev/null
          grep -F 'pi-provider-llama-swap' ${gallery}/index.ts >/dev/null
          grep -F 'pi-provider-omlx' ${gallery}/index.ts >/dev/null
        ''
      else
        ''
          ! grep -F 'pi-model-router' ${gallery}/index.ts >/dev/null
          ! grep -F 'pi-provider-llama-swap' ${gallery}/index.ts >/dev/null
          ! grep -F 'pi-provider-omlx' ${gallery}/index.ts >/dev/null
        ''
    }

    echo "Pi gallery check: dynamic local providers"
    ${bun}/bin/bun ${sourceForChecks}/packages/pi-gallery/providers/local-openai-provider.check.ts
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
      env -u OMLX_API_KEY -u LLAMA_SWAP_API_KEY \
      HOME="$routing_smoke/home" \
      PI_CODING_AGENT_DIR="$routing_smoke/agent" \
      PI_OFFLINE=1 \
        ${coreutils}/bin/timeout 60 \
        ${lib.getExe piPackage} \
        --print --offline --no-session --no-context-files \
        --no-extensions --no-skills --no-prompt-templates --no-approve \
        --extension ${routingExtension} \
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

    loop_smoke="$TMPDIR/pi-loop-smoke"
    mkdir -p "$loop_smoke/home" "$loop_smoke/agent"
    env -u OMLX_API_KEY -u LLAMA_SWAP_API_KEY \
      HOME="$loop_smoke/home" \
      PI_CODING_AGENT_DIR="$loop_smoke/agent" \
      PI_OFFLINE=1 \
        ${coreutils}/bin/timeout 60 \
        ${lib.getExe piPackage} \
        --print --offline --session "$loop_smoke/session.jsonl" --no-context-files \
        --no-extensions --no-skills --no-prompt-templates --no-approve \
        --extension ${piPackages.pi-loop}/share/pi-packages/pi-loop/extensions/index.ts \
        --extension "$routing_smoke/synthetic.ts" \
        --provider synthetic --model target \
        '/loop --yes --delay 0 --max 2 test' \
        </dev/null >"$loop_smoke/output" 2>"$loop_smoke/error" || {
      status=$?
      cat "$loop_smoke/error" >&2
      fail "pi-loop nested session-entry smoke failed with status $status"
    }
    jq -s -e '
      ([.[] | select(.type == "message" and .message.role == "user")] | length) == 2
      and ([.[] | select(.type == "message" and .message.role == "assistant")] | length) == 2
    ' "$loop_smoke/session.jsonl" >/dev/null || {
      cat "$loop_smoke/output" >&2
      cat "$loop_smoke/error" >&2
      fail "pi-loop did not complete two nested session-entry iterations"
    }
    loop_log=$(find "$loop_smoke/home/.pi/loops" -maxdepth 1 -type f -name 'loop-*.json' -print -quit)
    if [ -z "$loop_log" ] || ! jq -e '.entries | length == 2' "$loop_log" >/dev/null; then
      [ -z "$loop_log" ] || cat "$loop_log" >&2
      fail "pi-loop did not record two completed iterations"
    fi

    smoke="$TMPDIR/pi-gallery-smoke"
    mkdir -p \
      "$smoke/home/.config/pi/agent/extensions/nix-gallery" \
      "$smoke/home/.agents/skills/shared-discovery" \
      "$smoke/project" "$smoke/sentinels"
    ln -s "$smoke/home/.config/pi" "$smoke/home/.pi"
    ln -s ${gallery}/index.ts \
      "$smoke/home/.config/pi/agent/extensions/nix-gallery/index.ts"
    printf '%s\n' '{"providers":{"sentinel":{"apiKey":"unchanged"}}}' \
      > "$smoke/home/.config/pi/agent/models.json"
    cp "$smoke/home/.config/pi/agent/models.json" "$smoke/models-before.json"
    cat > "$smoke/home/.agents/skills/shared-discovery/SKILL.md" <<'MARKDOWN'
    ---
    name: shared-discovery
    description: Verify default shared skill discovery.
    ---

    # Shared discovery sentinel
    MARKDOWN
    printf '%s\n' '{"name":"lens-language-gate","private":true}' > "$smoke/project/package.json"
    printf '%s\n' 'const answer: number = 42;' > "$smoke/project/probe.ts"
    printf '%s\n' 'answer: int = 42' > "$smoke/project/probe.py"
    printf '%s\n' \
      '{"id":"commands","type":"get_commands"}' \
      '{"id":"ponytail","type":"prompt","message":"/ponytail ultra"}' \
      '{"id":"cache-fix","type":"prompt","message":"/cache-optimizer fix"}' \
      '{"id":"entries","type":"get_entries"}' > "$smoke/input.jsonl"
    for command in npm npx pip pip3 curl wget bun pnpm yarn; do
      cat > "$smoke/sentinels/$command" <<'SH'
    #!/bin/sh
    printf '%s\n' "$0 $*" >> "$PI_GALLERY_INSTALLER_SENTINEL"
    exit 97
    SH
      chmod +x "$smoke/sentinels/$command"
    done
    jq -r '.packages[].skills[]?' ${gallery}/projection.json \
      | while IFS= read -r skill_root; do
        find "$skill_root" -type f -name SKILL.md -print
      done \
      | sort -u > "$smoke/expected-skills"
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
      env -u PI_CODING_AGENT_DIR \
      HOME="$smoke/home" \
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
        ${python3}/bin/python3 "$rpc_sequence" \
        "$smoke/input.jsonl" \
        "$smoke/output.log" \
        "$smoke/error.log" \
        ${lib.getExe piPackage} \
        --mode rpc --no-session --offline \
        --no-prompt-templates \
        --no-context-files --no-approve \
        --extension "$smoke/active-tools.ts"
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
          "cache-optimizer",
          "caveman",
          "chain",
          "copy-message",
          "copy-user",
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
          ${lib.optionalString stdenv.hostPlatform.isDarwin ''"router",''}
          "rtk",
          "run",
          "subagents",
          "subagents-doctor",
          "subagents-fleet",
          "subagents-models",
          "subagents-watchdog",
          "trace",
          "usage",
          "viewer",
          "workflows"
        ] - [.data.commands[].name] | length) == 0
        and ([.data.commands[].name | select(startswith("sidebar"))] | length) == 0
      )
    ' "$smoke/output.log" >/dev/null || {
      cat "$smoke/output.log" >&2
      fail "new Pi gallery commands were not registered"
    }
    jq -s -e --arg skill "$smoke/home/.agents/skills/shared-discovery/SKILL.md" '
      any(
        .[];
        .type == "response"
        and .command == "get_commands"
        and .success == true
        and any(
          .data.commands[];
          .name == "skill:shared-discovery"
          and .source == "skill"
          and .sourceInfo.path == $skill
        )
      )
    ' "$smoke/output.log" >/dev/null || {
      cat "$smoke/output.log" >&2
      fail "Pi did not discover the shared skill tree through HOME"
    }
    # The trailing anvil clause is a prohibition, not a leftover reference. It
    # survives the Anvil retirement deliberately: retiring the convergence that
    # removed existing Anvil state is not the same as allowing the gallery to
    # advertise an Anvil tool again. It was deleted with that machinery in
    # cc0f6718 and restored in e5b7f905; a source search for "anvil" will find
    # this line, and it is the one that should stay.
    jq -e '
      . as $actual
      | ($actual | length) == ($actual | unique | length)
        and all(
          [
            "batch_web_fetch",
            "edit",
            "read",
            "recall",
            "web_fetch",
            "web_search",
            "write"
          ][];
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
    jq -e '.recall == ["blackhole"]' "$smoke/tool-owners.json" >/dev/null || {
      cat "$smoke/tool-owners.json" >&2
      fail "Pi memory tool does not have exactly one declared owner"
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
        .type == "extension_ui_request"
        and .method == "notify"
        and .notifyType == "warning"
        and .message == "Nix manages models.json; edit config/ai and switch the configuration instead."
      )
    ' "$smoke/output.log" >/dev/null || {
      cat "$smoke/output.log" >&2
      fail "Cache Optimizer did not refuse its models.json write path"
    }
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
    [ ! -e "$smoke/home/.config/pi/agent/settings.json" ] || fail "gallery wrote Pi settings"
    cmp -s "$smoke/models-before.json" "$smoke/home/.config/pi/agent/models.json" \
      || fail "Cache Optimizer changed Nix-managed models.json"
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
