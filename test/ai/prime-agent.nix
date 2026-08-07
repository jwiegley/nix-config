{
  jq,
  lib,
  pkgs,
  runCommand,
}:

let
  catalog = import ../../config/ai/catalog.nix {
    inherit lib;
    resources = pkgs.agent-resources;
  };
  profile = catalog.profiles.hera-prime;
  selected = lib.mapAttrs (_: items: catalog.select profile items) catalog.items;
  rendered = (import ../../config/ai/renderers/prime.nix { inherit lib pkgs; }) {
    inherit profile selected;
    homeDirectory = "/Users/johnw";
    xdgConfigHome = "/Users/johnw/.config";
  };
  root = ".prime/agent";
  settings = rendered.files."${root}/managed-settings.json".source;
  models = rendered.files."${root}/models.json".source;
  keybindings = rendered.files."${root}/keybindings.json".source;
  theme = rendered.files."${root}/themes/dark-tool-backgrounds.json".source;
  compatibility = rendered.files."${root}/COMPATIBILITY.md".text;
  agentNames = builtins.attrNames selected.agents;
  agentPrompts = map (name: rendered.files."${root}/prompts/agent-${name}.md".text) agentNames;
  commandName = builtins.head (builtins.attrNames selected.commands);
  commandSource = selected.commands.${commandName}.source;
  skillName = "skill-creator";
  skillSource = selected.skills.${skillName}.source;
  skillRoot =
    if builtins.baseNameOf skillSource == "SKILL.md" then builtins.dirOf skillSource else skillSource;
  mcpExtensionRoot = "${pkgs.agent-resources}/share/agent-resources/pi-extensions/pi-mcp-adapter";
  packageRoots = [
    "${pkgs.pi-gallery.packages.pi-provider-llama-swap}/share/pi-packages/pi-provider-llama-swap"
    "${pkgs.pi-gallery.packages.pi-provider-omlx}/share/pi-packages/pi-provider-omlx"
    mcpExtensionRoot
  ];
in
assert catalog.validate { };
assert builtins.length (builtins.attrNames rendered.files) == 93;
assert builtins.length agentNames == 25;
assert builtins.length (builtins.attrNames selected.commands) == 61;
assert builtins.length (builtins.attrNames selected.prompts) == 2;
assert builtins.length (builtins.attrNames selected.skills) == 24;
assert builtins.hasAttr skillName selected.skills;
assert !(builtins.hasAttr "${root}/settings.json" rendered.files);
assert builtins.hasAttr "${root}/managed-settings.json" rendered.files;
assert
  builtins.attrNames selected.mcpServers == [
    "devonthink"
    "drafts"
    "pal"
    "searxng"
    "sequential-thinking"
    "stock-trader"
  ];
assert builtins.all (
  text:
  lib.hasInfix "native `rlm`" text
  && lib.hasInfix "agent_message" text
  && lib.hasInfix "without an explicit" text
  && !lib.hasInfix "persistent child named" text
  && !lib.hasInfix "$@" text
  && builtins.length (lib.splitString "$ARGUMENTS" text) == 2
) agentPrompts;
assert lib.hasInfix "stdio servers" compatibility;
assert lib.hasInfix "secret-command-backed" compatibility;
runCommand "prime-agent-integration-check"
  {
    nativeBuildInputs = [ jq ];
  }
  ''
    set -euo pipefail

    test "$(jq -r '.defaultThinkingLevel' ${settings})" = xhigh
    test "$(jq -r '.theme' ${settings})" = dark-tool-backgrounds
    test "$(jq '.packages | length' ${settings})" -eq 3
    test "$(jq '.enableBuiltinSkills and .enableSkillCommands' ${settings})" = true
    test "$(jq '.skills == ["-skill-creator/SKILL.md"]' ${settings})" = true
    test "$(jq 'has("mcpServers")' ${settings})" = false

    test "$(jq '.providers | keys == ["llama-swap", "omlx", "openai-codex", "openrouter"]' ${models})" = true
    test "$(jq '[.. | objects | select(has("apiKey"))] | length' ${models})" -eq 0
    test "$(jq -r '.providers["openai-codex"].modelOverrides["gpt-5.6-sol"].contextWindow' ${models})" -eq 1050000
    test "$(jq -r '.providers.openrouter.modelOverrides["z-ai/glm-5.2"].contextWindow' ${models})" -eq 1048576
    test "$(jq -r '.providers["llama-swap"].modelOverrides["GLM-5.2"].contextWindow' ${models})" -eq 262144
    test "$(jq -r '.providers.omlx.modelOverrides["DeepSeek-V4-Flash-0731-oQ8e-mtp"].contextWindow' ${models})" -eq 262144

    test "$(jq 'keys | length' ${keybindings})" -eq 10
    test "$(jq 'has("app.model.cycleForward") or has("app.model.cycleBackward")' ${keybindings})" = false
    test "$(jq '.colors | keys | length' ${theme})" -eq 55
    test "$(jq '.colors | has("bashMode") and (has("thinkingMax") | not)' ${theme})" = true
    test "$(jq '.colors | has("toolPanelBg") and has("toolDiffAddedBg") and has("toolDiffRemovedBg")' ${theme})" = true

    ${lib.concatMapStringsSep "\n" (
      path: "test -f ${lib.escapeShellArg "${path}/package.json"}"
    ) packageRoots}
    test "$(${pkgs.prime-agent}/bin/prime-agent --version 2>&1)" = 0.7.0
    test "$(jq -r .version ${pkgs.prime-agent}/lib/prime-agent/package.json)" = 0.7.0
    for package in pi-agent-core pi-ai pi-tui; do
      test "$(jq -r .version ${pkgs.prime-agent}/lib/prime-agent/node_modules/@earendil-works/$package/package.json)" = 0.7.0
    done
    ${pkgs.prime-agent}/bin/prime-agent --help >help.out 2>&1
    grep -F 'prime-agent - AI coding assistant' help.out >/dev/null
    grep -F 'prime-agent <command>' help.out >/dev/null

    (
      cd ${pkgs.prime-agent}/lib/prime-agent
      ${pkgs.nodejs_24}/bin/node --input-type=module <<'JS'
    for (const [name, key] of [["undici", "fetch"], ["@silvia-odwyer/photon-node", "PhotonImage"], ["zeromq", "Request"], ["@earendil-works/pi-ai", "getModel"]]) {
      const module = await import(name);
      if (!(key in module)) throw new Error("invalid runtime module: " + name);
    }
    JS
    )

    home=$TMPDIR/home
    mkdir -m 700 -p \
      "$home/.prime/agent/extensions" \
      "$home/.prime/agent/prompts" \
      "$home/.prime/agent/themes" \
      "$home/.agents/skills" \
      "$home/.config/mcp"
    ln -s ${settings} "$home/.prime/agent/managed-settings.json"
    printf '%s\n' '{"onboardingShown":false}' >"$home/.prime/agent/settings.json"
    chmod 600 "$home/.prime/agent/settings.json"
    install -m 600 ${models} "$home/.prime/agent/models.json"
    install -m 600 ${keybindings} "$home/.prime/agent/keybindings.json"
    install -m 600 ${theme} "$home/.prime/agent/themes/dark-tool-backgrounds.json"
    install -m 600 ${commandSource} "$home/.prime/agent/prompts/${commandName}.md"
    printf '%s\n' ${lib.escapeShellArg (builtins.head agentPrompts)} > "$home/.prime/agent/prompts/agent-${builtins.head agentNames}.md"
    cp -R ${skillRoot} "$home/.agents/skills/${skillName}"
    cat >synthetic-mcp.mjs <<'JS'
    import { Server } from "file://${mcpExtensionRoot}/node_modules/@modelcontextprotocol/sdk/dist/esm/server/index.js";
    import { StdioServerTransport } from "file://${mcpExtensionRoot}/node_modules/@modelcontextprotocol/sdk/dist/esm/server/stdio.js";
    import { CallToolRequestSchema, ListToolsRequestSchema } from "file://${mcpExtensionRoot}/node_modules/@modelcontextprotocol/sdk/dist/esm/types.js";

    const server = new Server(
      { name: "nix-prime-synthetic", version: "1.0.0" },
      { capabilities: { tools: {} } },
    );
    server.setRequestHandler(ListToolsRequestSchema, async () => ({
      tools: [{
        name: "echo",
        description: "Return the supplied synthetic value",
        inputSchema: {
          type: "object",
          properties: { value: { type: "string" } },
          required: ["value"],
          additionalProperties: false,
        },
      }],
    }));
    server.setRequestHandler(CallToolRequestSchema, async (request) => {
      if (request.params.name !== "echo") throw new Error("unexpected synthetic tool");
      const value = request.params.arguments?.value;
      if (typeof value !== "string") throw new Error("synthetic value must be a string");
      return { content: [{ type: "text", text: "synthetic-mcp:" + value }] };
    });
    await server.connect(new StdioServerTransport());
    JS
    chmod 600 synthetic-mcp.mjs
    cat > "$home/.config/mcp/mcp.json" <<JSON
    {"mcpServers":{"synthetic":{"command":"${pkgs.nodejs_24}/bin/node","args":["$TMPDIR/synthetic-mcp.mjs"]}},"settings":{"mcpFooterStatus":"compact"}}
    JSON
    chmod 600 "$home/.config/mcp/mcp.json"
    cat >"$home/.prime/agent/extensions/root-contract.ts" <<'TS'
    export default function rootContract() {
      if (process.env.PI_CODING_AGENT_DIR !== process.env.PRIME_AGENT_CODING_AGENT_DIR) {
        throw new Error("Prime and adapter roots diverged");
      }
    }
    TS
    chmod 600 "$home/.prime/agent/extensions/root-contract.ts"
    cat >resource-check.mjs <<'JS'
    import { existsSync, readFileSync } from "node:fs";
    import {
      DefaultResourceLoader,
      SessionManager,
      SettingsManager,
      createAgentSession,
    } from "file://${pkgs.prime-agent}/lib/prime-agent/dist/index.js";
    import {
      createAssistantMessageEventStream,
      registerApiProvider,
    } from "file://${pkgs.prime-agent}/lib/prime-agent/node_modules/@earendil-works/pi-ai/dist/index.js";

    const check = (condition, message) => {
      if (!condition) throw new Error(message);
    };
    const home = process.env.HOME;
    const agentDir = home + "/.prime/agent";
    const settingsManager = SettingsManager.create(home, agentDir);
    const managedBefore = readFileSync(agentDir + "/managed-settings.json", "utf8");
    check(settingsManager.getTheme() === "dark-tool-backgrounds", "managed theme was not effective");
    settingsManager.setOnboardingShown(true);
    settingsManager.setTheme("mutable-attempt");
    await settingsManager.flush();
    const mutableSettings = JSON.parse(readFileSync(agentDir + "/settings.json", "utf8"));
    check(mutableSettings.onboardingShown === true, "mutable onboarding state did not persist");
    check(mutableSettings.theme === "mutable-attempt", "mutable preference write did not persist");
    check(settingsManager.getTheme() === "dark-tool-backgrounds", "mutable settings displaced managed policy");
    check(
      readFileSync(agentDir + "/managed-settings.json", "utf8") === managedBefore,
      "managed settings changed during a mutable preference write",
    );
    const loader = new DefaultResourceLoader({ cwd: home, agentDir, settingsManager });
    await loader.reload();

    const prompts = new Set(loader.getPrompts().prompts.map((prompt) => prompt.name));
    check(prompts.has("${commandName}"), "managed command prompt was not discovered");
    check(prompts.has("agent-${builtins.head agentNames}"), "RLM specialist prompt was not discovered");
    check(loader.getPrompts().diagnostics.length === 0, "prompt diagnostics were not empty");

    const discoveredSkills = loader.getSkills().skills;
    const skills = new Set(discoveredSkills.map((skill) => skill.name));
    const skillCreators = discoveredSkills.filter((skill) => skill.name === "skill-creator");
    check(skillCreators.length === 1, "skill-creator was missing or duplicated");
    check(
      skillCreators[0].filePath === home + "/.agents/skills/skill-creator/SKILL.md",
      "Prime's built-in skill-creator displaced the shared managed skill",
    );
    check(skills.has("rlm-heartbeat"), "Prime Agent's built-in RLM skill was not discovered");
    check(loader.getSkills().diagnostics.length === 0, "skill diagnostics were not empty");

    const extensions = loader.getExtensions();
    check(extensions.errors.length === 0, "extension loader reported an error");
    const loadedPaths = loader.getLoadedExtensionPaths();
    for (const root of ${builtins.toJSON packageRoots}) {
      check(loadedPaths.some((path) => path.startsWith(root + "/")), "managed extension package was not loaded: " + root);
    }
    const providers = extensions.runtime.pendingProviderRegistrations.map((entry) => entry.name).sort();
    check(JSON.stringify(providers) === JSON.stringify(["llama-swap", "omlx"]), "local provider registrations differ");
    check(
      extensions.extensions.some((extension) =>
        extension.tools.has("mcp") && extension.commands.has("mcp") && extension.commands.has("mcp-auth")
      ),
      "MCP adapter tools and commands were not registered",
    );

    const syntheticModel = {
      id: "nix-synthetic-model",
      name: "Nix synthetic provider",
      api: "nix-synthetic-api",
      provider: "nix-synthetic-provider",
      baseUrl: "http://127.0.0.1.invalid",
      reasoning: false,
      input: ["text"],
      cost: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0 },
      contextWindow: 4096,
      maxTokens: 256,
    };
    const syntheticStream = (_model, context) => {
      const stream = createAssistantMessageEventStream();
      queueMicrotask(() => {
        const last = context.messages.at(-1);
        const userText = !last || last.role !== "user"
          ? ""
          : typeof last.content === "string"
            ? last.content
            : last.content.filter((item) => item.type === "text").map((item) => item.text).join("\n");
        stream.push({
          type: "done",
          reason: "stop",
          message: {
            role: "assistant",
            content: [{ type: "text", text: "synthetic-provider:" + userText }],
            api: syntheticModel.api,
            provider: syntheticModel.provider,
            model: syntheticModel.id,
            usage: {
              input: 1,
              output: 1,
              cacheRead: 0,
              cacheWrite: 0,
              totalTokens: 2,
              cost: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0, total: 0 },
            },
            stopReason: "stop",
            timestamp: Date.now(),
          },
        });
      });
      return stream;
    };
    registerApiProvider({
      api: syntheticModel.api,
      stream: syntheticStream,
      streamSimple: syntheticStream,
    }, "nix-prime-integration-check");

    const { session } = await createAgentSession({
      cwd: home,
      agentDir,
      model: syntheticModel,
      thinkingLevel: "off",
      resourceLoader: loader,
      settingsManager,
      sessionManager: SessionManager.inMemory(home),
      prewarmIpythonKernel: false,
    });
    const tools = session.getAllTools();
    const ipython = tools.find((tool) => tool.name === "ipython");
    check(ipython, "native IPython tool is unavailable");
    check(
      readFileSync("${pkgs.prime-agent}/lib/prime-agent/dist/core/tools/ipython.js", "utf8").includes(
        "rlm = _prime_agent_rlm_module.rlm",
      ),
      "native IPython-to-RLM bridge is unavailable",
    );
    check(tools.some((tool) => tool.name === "mcp"), "MCP tool is unavailable in the session");
    await session.promptAndWait("provider-round-trip");
    const providerReply = session.state.messages.findLast((message) => message.role === "assistant");
    const providerText = providerReply?.content
      .filter((item) => item.type === "text")
      .map((item) => item.text)
      .join("\n");
    check(
      providerText === "synthetic-provider:provider-round-trip",
      "synthetic provider request did not complete a full turn",
    );
    const child = await session.runRlmChild("rlm-round-trip", { name: "nix-prime-rlm-check" });
    check(child.rlm_child_id.startsWith("sub-"), "native RLM did not admit a child");
    const rlmDeadline = Date.now() + 10000;
    while (["queued", "running"].includes(session.getRlmChildRunStatus(child.rlm_child_id))) {
      if (Date.now() >= rlmDeadline) throw new Error("native RLM child did not reach a terminal state");
      await new Promise((resolve) => setTimeout(resolve, 10));
    }
    check(session.getRlmChildRunStatus(child.rlm_child_id) === "done", "native RLM child did not finish");
    const subagents = await session.listRlmSubagents();
    check(
      subagents.subagents.some((subagent) => subagent.rlm_child_id === child.rlm_child_id),
      "native RLM child was absent from the parent registry",
    );
    const deletedChild = await session.deleteRlmSubagent(child.rlm_child_id);
    check(deletedChild.outcome === "deleted", "native RLM child cleanup did not complete");
    const mcp = session.getToolDefinition("mcp");
    check(mcp, "MCP tool definition is unavailable");
    const mcpResult = await mcp.execute(
      "nix-synthetic-mcp-call",
      { tool: "echo", server: "synthetic", args: { value: "round-trip" } },
      undefined,
      undefined,
      {},
    );
    const mcpText = mcpResult.content
      .filter((item) => item.type === "text")
      .map((item) => item.text)
      .join("\n");
    check(mcpText.includes("synthetic-mcp:round-trip"), "synthetic MCP invocation did not round-trip");
    check(
      existsSync("${pkgs.prime-agent}/lib/prime-agent/dist/prime-agent-runtime/src/rlm/__init__.py"),
      "bundled native RLM runtime is missing",
    );
    await session.dispose();
    JS
    HOME="$home" XDG_CONFIG_HOME="$home/.config" \
      PRIME_AGENT_CODING_AGENT_DIR="$home/.prime/agent" \
      PRIME_AGENT_MANAGED_SETTINGS="$home/.prime/agent/managed-settings.json" \
      PI_CODING_AGENT_DIR="$home/.prime/agent" \
      PI_PACKAGE_DIR="${pkgs.prime-agent}/lib/prime-agent" \
      PRIME_AGENT_INSTALL_UV=0 \
      ${pkgs.nodejs_24}/bin/node resource-check.mjs
    daemon_tmp="$TMPDIR/prime-daemon"
    daemon_socket="$daemon_tmp/daemon.sock"
    mkdir -m 700 "$daemon_tmp"
    daemon_pid=
    cleanup_daemon() {
      if [ -n "$daemon_pid" ] && kill -0 "$daemon_pid" 2>/dev/null; then
        kill "$daemon_pid" 2>/dev/null || true
        wait "$daemon_pid" 2>/dev/null || true
      fi
    }
    trap cleanup_daemon EXIT HUP INT TERM
    HOME="$home" XDG_CONFIG_HOME="$home/.config" TMPDIR="$daemon_tmp" PI_OFFLINE=1 \
      PRIME_AGENT_CODING_AGENT_DIR="$home/.prime/agent" \
      PRIME_AGENT_MANAGED_SETTINGS="$home/.prime/agent/managed-settings.json" \
      PI_CODING_AGENT_DIR="$home/.prime/agent" \
      ${pkgs.prime-agent}/bin/prime-agent \
        --mode daemon --offline --daemon-socket "$daemon_socket" --no-session \
        --no-extensions --no-skills --no-prompt-templates --no-context-files \
        >daemon.out 2>daemon.err &
    daemon_pid=$!
    for _ in $(seq 1 200); do
      [ -S "$daemon_socket" ] && break
      kill -0 "$daemon_pid" 2>/dev/null || {
        cat daemon.err >&2
        exit 1
      }
      sleep 0.05
    done
    test -S "$daemon_socket"
    HOME="$home" XDG_CONFIG_HOME="$home/.config" TMPDIR="$daemon_tmp" \
      PRIME_AGENT_CODING_AGENT_DIR="$home/.prime/agent" \
      PRIME_AGENT_MANAGED_SETTINGS="$home/.prime/agent/managed-settings.json" \
      PI_CODING_AGENT_DIR="$home/.prime/agent" \
      ${pkgs.prime-agent}/bin/prime-agent --daemon-socket "$daemon_socket" status --json \
      >daemon-status.json
    jq -e '.daemon.running == true or .running == true' daemon-status.json >/dev/null
    HOME="$home" XDG_CONFIG_HOME="$home/.config" TMPDIR="$daemon_tmp" \
      PRIME_AGENT_CODING_AGENT_DIR="$home/.prime/agent" \
      PRIME_AGENT_MANAGED_SETTINGS="$home/.prime/agent/managed-settings.json" \
      PI_CODING_AGENT_DIR="$home/.prime/agent" \
      ${pkgs.prime-agent}/bin/prime-agent --daemon-socket "$daemon_socket" shutdown --force --json \
      >daemon-shutdown.json
    wait "$daemon_pid"
    daemon_pid=
    test ! -S "$daemon_socket"
    trap - EXIT HUP INT TERM

    HOME="$home" XDG_CONFIG_HOME="$home/.config" PI_OFFLINE=1 \
      PI_CODING_AGENT_DIR="$home/poison-pi-root" \
      PRIME_AGENT_CODING_AGENT_DIR="$home/.prime/agent" \
      ${pkgs.prime-agent}/bin/prime-agent model list --offline >model-list.out 2>model-list.err
    ! grep -E '(Failed to load extension|Cannot find package|Invalid theme|Invalid skill|TypeError|ReferenceError)' \
      model-list.out model-list.err
    test ! -e "$home/poison-pi-root"
    test ! -e "$home/.prime/agent/daemon-workers"
    test ! -e "$home/.prime/agent/kernel-venv"

    mkdir -p "$out"
    cp ${settings} "$out/managed-settings.json"
    cp ${models} "$out/models.json"
    cp ${keybindings} "$out/keybindings.json"
    cp ${theme} "$out/theme.json"
    printf '%s\n' ${lib.escapeShellArg compatibility} > "$out/COMPATIBILITY.md"
    touch "$out/passed"
  ''
