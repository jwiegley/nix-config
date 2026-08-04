{ lib, pkgs }:

{
  profile,
  selected,
  homeDirectory,
  xdgConfigHome,
}:

let
  root = ".config/pi/agent";
  json = pkgs.formats.json { };
  mergeFiles = import ./merge-files.nix { inherit lib; };

  hasOnlyKeys =
    allowed: value: builtins.all (name: builtins.elem name allowed) (builtins.attrNames value);
  isTypedEnv =
    value:
    builtins.isAttrs value
    && builtins.attrNames value == [ "env" ]
    && builtins.isString value.env
    && builtins.match "^[A-Z][A-Z0-9_]*$" value.env != null;
  isSafeUrl =
    value:
    builtins.isString value
    && builtins.all (fragment: !(lib.hasInfix fragment value)) [
      "$"
      "{env:"
      "$env:"
      "?apiKey="
    ];
  mcpRequiredEnvNames = lib.concatMap (
    server:
    lib.concatMap (value: lib.optional (isTypedEnv value) value.env) (
      builtins.attrValues (server.transport.env or { })
      ++ builtins.attrValues (server.transport.headers or { })
    )
  ) (builtins.attrValues selected.mcpServers);
  renderEnv = name: "$" + "{" + name + "}";
  localModelRoutes = profile.platform == "darwin";

  routerTarget = {
    id = "Qwen3.6-27B-oQ6e-mtp";
    contextLimit = 262144;
    outputLimit = 65536;
  };
  routerProvider = {
    api = "router-local-api";
    apiKey = "pi-model-router";
    baseUrl = "router://local";
    models = [
      {
        id = "sol";
        name = "Router sol";
        reasoning = true;
        input = [
          "text"
          "image"
        ];
        cost = {
          input = 0;
          output = 0;
          cacheRead = 0;
          cacheWrite = 0;
        };
        contextWindow = routerTarget.contextLimit;
        maxTokens = routerTarget.outputLimit;
        thinkingLevelMap.xhigh = "xhigh";
      }
    ];
  };
  nativeProviders = {
    openai-codex.modelOverrides."gpt-5.6-sol".contextWindow = 1050000;
    openrouter.modelOverrides."z-ai/glm-5.2".contextWindow = 1048576;
  };
  localProviders = {
    llama-swap.modelOverrides."GLM-5.2".contextWindow = 262144;
    omlx.modelOverrides."DeepSeek-V4-Flash-0731-oQ8e-mtp".contextWindow = 262144;
    router = routerProvider;
  };
  models.providers = nativeProviders // lib.optionalAttrs localModelRoutes localProviders;
  modelRouter = {
    debug = false;
    phaseBias = 0.5;
    models.sol = {
      model = "omlx/${routerTarget.id}";
      contextWindow = routerTarget.contextLimit;
      maxTokens = routerTarget.outputLimit;
      reasoning = true;
      thinkingLevels = [
        "low"
        "medium"
        "high"
        "xhigh"
      ];
    };
    profiles.sol = {
      high = {
        model = "sol";
        thinking = "xhigh";
      };
      medium = {
        model = "sol";
        thinking = "medium";
      };
      low = {
        model = "sol";
        thinking = "low";
      };
    };
  };

  renderMcpEnvValue =
    value:
    if isTypedEnv value then
      renderEnv value.env
    else if builtins.isString value then
      value
    else
      throw "unsupported Pi MCP environment value";
  renderMcpServer =
    _: server:
    let
      inherit (server) transport;
    in
    if transport ? url then
      assert hasOnlyKeys [
        "headers"
        "url"
      ] transport;
      assert isSafeUrl transport.url;
      assert !(transport ? headers) || builtins.all isTypedEnv (builtins.attrValues transport.headers);
      {
        inherit (transport) url;
        oauth = false;
      }
      // lib.optionalAttrs (transport ? headers) {
        headers = lib.mapAttrs (_: reference: renderEnv reference.env) transport.headers;
      }
    else
      assert hasOnlyKeys [
        "args"
        "command"
        "env"
      ] transport;
      assert builtins.isString transport.command;
      assert builtins.isList transport.args && builtins.all builtins.isString transport.args;
      {
        inherit (transport) command args;
      }
      // lib.optionalAttrs (transport ? env) {
        env = lib.mapAttrs (_: renderMcpEnvValue) transport.env;
      };
  mcp = {
    mcpServers = lib.mapAttrs renderMcpServer selected.mcpServers;
    settings.mcpFooterStatus = "compact";
  };
  keybindings = {
    "tui.editor.cursorUp" = [
      "up"
      "ctrl+p"
    ];
    "tui.editor.cursorDown" = [
      "down"
      "ctrl+n"
    ];
    "tui.editor.cursorLeft" = [
      "left"
      "ctrl+b"
    ];
    "tui.editor.cursorRight" = [
      "right"
      "ctrl+f"
    ];
    "tui.editor.cursorWordLeft" = [
      "alt+left"
      "alt+b"
    ];
    "tui.editor.cursorWordRight" = [
      "alt+right"
      "alt+f"
    ];
    "tui.editor.deleteCharForward" = [
      "delete"
      "ctrl+d"
    ];
    "tui.editor.deleteCharBackward" = [
      "backspace"
      "ctrl+h"
    ];
    "tui.input.newLine" = [
      "shift+enter"
      "ctrl+j"
    ];
    "app.model.select" = [ "ctrl+l" ];
    "app.model.cycleForward" = [ ];
    "app.model.cycleBackward" = [ ];
  };

  renderAgentTools =
    tools:
    if tools == "Read, Grep, Glob, Bash" then
      "read,grep,find,bash"
    else
      throw "unsupported Pi agent tools: ${builtins.toJSON tools}";
  renderAgentMetadata =
    item:
    assert hasOnlyKeys [
      "description"
      "name"
      "tools"
    ] item.metadata;
    builtins.removeAttrs item.metadata [ "tools" ]
    // lib.optionalAttrs (item.metadata ? tools) {
      tools = renderAgentTools item.metadata.tools;
    };
  renderCommandMetadata =
    item:
    assert hasOnlyKeys [
      "allowed-tools"
      "argument-hint"
      "description"
      "disable-model-invocation"
    ] item.metadata;
    assert !(item.metadata ? description) || builtins.isString item.metadata.description;
    lib.optionalAttrs (item.metadata ? description) {
      inherit (item.metadata) description;
    }
    //
      lib.optionalAttrs
        (builtins.hasAttr "argument-hint" item.metadata && builtins.isString item.metadata."argument-hint")
        {
          "argument-hint" = item.metadata."argument-hint";
        };
  renderMarkdown =
    metadata: source:
    if metadata == { } then
      builtins.readFile source
    else
      "---\n${builtins.toJSON metadata}\n---\n${builtins.readFile source}";

  agentFiles = lib.mapAttrs' (
    name: item:
    lib.nameValuePair "${root}/agents/${name}.md" {
      text = renderMarkdown (renderAgentMetadata item) item.source;
    }
  ) selected.agents;
  commandFiles = lib.mapAttrs' (
    name: item:
    lib.nameValuePair "${root}/prompts/${name}.md" {
      text = renderMarkdown (renderCommandMetadata item) item.source;
    }
  ) selected.commands;
  promptFiles = lib.mapAttrs' (
    name: item:
    lib.nameValuePair "${root}/prompts/${name}.md" {
      inherit (item) source;
    }
  ) selected.prompts;

  xdgConfigRelative = lib.removePrefix "${homeDirectory}/" xdgConfigHome;
  globalMcpPath = "${xdgConfigRelative}/mcp/mcp.json";
  extensionRoot = "${pkgs.agent-resources}/share/agent-resources/pi-extensions";
  autoCompactResumeSource = ../extensions/auto-compact-resume/index.ts;
  fleetThemeSource = ../extensions/fleet-theme/index.ts;
  fleetTheme = ../themes/dark-tool-backgrounds.json;
in
assert profile.id == "${profile.host}-pi";
assert profile.client == "pi";
assert profile.renderer == "pi";
assert builtins.elem profile.host [
  "clio"
  "hera"
  "shared-work"
  "vps"
  "vulcan"
];
assert
  profile.platform == (
    if
      builtins.elem profile.host [
        "clio"
        "hera"
      ]
    then
      "darwin"
    else
      "linux"
  );
assert profile.audiences == [ "personal" ];
assert profile.root == root;
assert builtins.isString homeDirectory;
assert xdgConfigHome == "${homeDirectory}/.config";
assert selected.hooks == { };
assert selected.marketplaces == { };
assert selected.settings == { };
assert mcp.settings.mcpFooterStatus == "compact";
assert
  builtins.attrNames models.providers == (
    if localModelRoutes then
      [
        "llama-swap"
        "omlx"
        "openai-codex"
        "openrouter"
        "router"
      ]
    else
      [
        "openai-codex"
        "openrouter"
      ]
  );
assert
  !localModelRoutes || models.providers.llama-swap.modelOverrides."GLM-5.2".contextWindow == 262144;
assert
  !localModelRoutes
  || models.providers.omlx.modelOverrides."DeepSeek-V4-Flash-0731-oQ8e-mtp".contextWindow == 262144;
assert models.providers.openai-codex.modelOverrides."gpt-5.6-sol".contextWindow == 1050000;
assert models.providers.openrouter.modelOverrides."z-ai/glm-5.2".contextWindow == 1048576;
assert routerTarget.id == "Qwen3.6-27B-oQ6e-mtp";
assert routerTarget.contextLimit == 262144;
assert routerTarget.outputLimit == 65536;
assert
  lib.intersectLists (builtins.attrNames selected.commands) (builtins.attrNames selected.prompts)
  == [ ];
assert builtins.hasAttr "agent-resources" pkgs;
assert builtins.hasAttr "pi-gallery" pkgs;
assert builtins.hasAttr "pi-loop" pkgs.pi-gallery.packages;
{
  files = mergeFiles [
    agentFiles
    commandFiles
    promptFiles
    {
      ".pi-lens/config.json".source = json.generate "pi-${profile.id}-lens.json" {
        widget.visible = false;
      };
      "${root}/extensions/auto-compact-resume/index.ts".source = autoCompactResumeSource;
      "${root}/extensions/fleet-theme/index.ts".source = fleetThemeSource;
      "${root}/extensions/nix-gallery/index.ts".source = "${pkgs.pi-gallery}/share/pi-gallery/index.ts";
      "${root}/extensions/pi-loop/index.ts".source =
        "${pkgs.pi-gallery.packages.pi-loop}/share/pi-packages/pi-loop/extensions/index.ts";
      "${root}/extensions/pi-mcp-adapter".source = "${extensionRoot}/pi-mcp-adapter";
      "${root}/extensions/pi-quiet".source = "${extensionRoot}/pi-quiet";
      "${root}/keybindings.json".source = json.generate "pi-${profile.id}-keybindings.json" keybindings;
      "${root}/models.json".source = json.generate "pi-${profile.id}-models.json" models;
      "${root}/themes/dark-tool-backgrounds.json".source = fleetTheme;
      "${globalMcpPath}".source = json.generate "pi-${profile.id}-mcp.json" mcp;
    }
    (lib.optionalAttrs localModelRoutes {
      "${root}/model-router.json".source = json.generate "pi-${profile.id}-model-router.json" modelRouter;
    })
  ];

  companions = [ ];

  requiredEnvNames = lib.unique (lib.sort builtins.lessThan mcpRequiredEnvNames);

  mutableMcpGuard = {
    path = ".config/pi/agent/mcp.json";
    forbiddenKeys = [
      "mcpServers"
      "imports"
    ];
  };
}
