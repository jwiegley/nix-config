{ lib, pkgs }:

{
  profile,
  selected,
  modelData,
  homeDirectory,
  xdgConfigHome,
}:

let
  root = ".pi/agent";
  json = pkgs.formats.json { };
  mergeFiles = import ./merge-files.nix { inherit lib; };

  expectedProviderNames = [ "litellm" ];
  expectedMcpNames = [
    "Ref"
    "anvil"
    "context-hub"
    "context7"
    "devonthink"
    "drafts"
    "memory-vault"
    "pal"
    "perplexity"
    "sequential-thinking"
    "stock-trader"
  ];
  expectedHttpHeaders = {
    Ref = "x-ref-api-key";
    context7 = "CONTEXT7_API_KEY";
  };

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
  providerRequiredEnvNames = lib.concatMap (
    providerName:
    let
      provider = modelData.providers.${providerName};
    in
    lib.optional (providerName != "litellm" && isTypedEnv provider.apiKey) provider.apiKey.env
  ) (builtins.attrNames modelData.providers);
  mcpRequiredEnvNames = lib.concatMap (
    server:
    lib.concatMap (value: lib.optional (isTypedEnv value) value.env) (
      builtins.attrValues (server.transport.env or { })
      ++ builtins.attrValues (server.transport.headers or { })
    )
  ) (builtins.attrValues selected.mcpServers);
  renderEnv = name: "$" + "{" + name + "}";
  piLiteLLMApiKeyHelper = pkgs.writeShellScript "pi-litellm-api-key" ''
    set -euo pipefail
    set +x

    pass_bin=''${PI_LITELLM_PASS_BIN:-${lib.getExe pkgs.pass}}
    credential=""
    if [[ ! -x $pass_bin ]] || ! credential="$("$pass_bin" litellm.vulcan.lan)"; then
      echo "pi: LiteLLM credential is unavailable or empty" >&2
      exit 1
    fi
    credential=''${credential%%$'\n'*}
    if [[ -z $credential ]]; then
      echo "pi: LiteLLM credential is unavailable or empty" >&2
      exit 1
    fi
    printf '%s\n' "$credential"
  '';
  piLiteLLMApiKeyCommand = "!${piLiteLLMApiKeyHelper}";

  orderedValues =
    set: lib.sort (left: right: left.sourceOrder < right.sourceOrder) (builtins.attrValues set);
  renderModel =
    model:
    assert builtins.isString model.id;
    assert builtins.isString model.displayName;
    assert model ? outputLimit || model ? maxOutputTokens;
    {
      inherit (model) id;
      name = model.displayName;
      maxTokens = model.outputLimit or model.maxOutputTokens;
    }
    // lib.optionalAttrs (model ? contextLimit) {
      contextWindow = model.contextLimit;
    }
    // lib.optionalAttrs (model.provider == "litellm" && model.id == "positron_openai/gpt-5.6-sol") {
      api = "openai-responses";
      reasoning = true;
      input = [
        "text"
        "image"
      ];
      cost = {
        input = 5;
        output = 30;
        cacheRead = 0.5;
        cacheWrite = 6.25;
        tiers = [
          {
            inputTokensAbove = 272000;
            input = 10;
            output = 45;
            cacheRead = 1;
            cacheWrite = 12.5;
          }
        ];
      };
      thinkingLevelMap = {
        off = "none";
        minimal = null;
        xhigh = "xhigh";
        max = null;
      };
    };
  solModels = orderedValues (
    lib.filterAttrs (
      _: model: model.provider == "litellm" && model.id == "positron_openai/gpt-5.6-sol"
    ) modelData.models
  );
  solModel = builtins.head solModels;
  renderProvider =
    providerName: provider:
    assert providerName == "litellm";
    {
      apiKey = piLiteLLMApiKeyCommand;
      inherit (provider) baseUrl;
      models = map renderModel solModels;
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
        contextWindow = solModel.contextLimit;
        maxTokens = solModel.outputLimit;
        thinkingLevelMap.xhigh = "xhigh";
      }
    ];
  };
  models = {
    providers = lib.mapAttrs renderProvider modelData.providers // {
      router = routerProvider;
    };
  };
  modelRouter = {
    debug = false;
    phaseBias = 0.5;
    models.sol = {
      model = "litellm/${solModel.id}";
      contextWindow = solModel.contextLimit;
      maxTokens = solModel.outputLimit;
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
    name: server:
    let
      inherit (server) transport;
    in
    if transport ? url then
      assert hasOnlyKeys [
        "headers"
        "url"
      ] transport;
      assert isSafeUrl transport.url;
      assert
        if transport ? headers then
          builtins.hasAttr name expectedHttpHeaders
          && builtins.attrNames transport.headers == [ expectedHttpHeaders.${name} ]
          && isTypedEnv transport.headers.${expectedHttpHeaders.${name}}
        else
          !(builtins.hasAttr name expectedHttpHeaders);
      {
        inherit (transport) url;
        oauth = false;
      }
      // lib.optionalAttrs (transport ? headers) {
        headers = lib.mapAttrs (_: reference: renderEnv reference.env) transport.headers;
      }
    else
      assert !(builtins.hasAttr name expectedHttpHeaders);
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
  };

  renderAgentTools =
    tools:
    if tools == "Read, Grep, Glob, Bash" then
      "read,grep,find,bash"
    else if
      tools == [
        "mcp__perplexity__perplexity_search_web"
        "WebFetch"
      ]
    then
      "mcp"
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
in
assert profile.id == "hera-pi";
assert profile.client == "pi";
assert profile.renderer == "pi";
assert profile.host == "hera";
assert profile.platform == "darwin";
assert profile.audiences == [ "personal" ];
assert profile.root == root;
assert builtins.isString homeDirectory;
assert xdgConfigHome == "${homeDirectory}/.config";
assert builtins.length (builtins.attrNames selected.agents) == 26;
assert builtins.length (builtins.attrNames selected.commands) == 59;
assert builtins.length (builtins.attrNames selected.prompts) == 82;
assert builtins.length (builtins.attrNames selected.skills) == 104;
assert selected.hooks == { };
assert selected.marketplaces == { };
assert selected.settings == { };
assert builtins.attrNames selected.mcpServers == expectedMcpNames;
assert builtins.attrNames modelData.providers == expectedProviderNames;
assert builtins.length solModels == 1;
assert solModel.contextLimit == 1050000;
assert solModel.outputLimit == 128000;
assert !(modelData ? default);
assert builtins.all (model: builtins.hasAttr model.provider modelData.providers) (
  builtins.attrValues modelData.models
);
assert
  lib.intersectLists (builtins.attrNames selected.commands) (builtins.attrNames selected.prompts)
  == [ ];
assert builtins.hasAttr "agent-resources" pkgs;
assert builtins.hasAttr "pi-gallery" pkgs;
assert builtins.hasAttr "pass" pkgs;
{
  files = mergeFiles [
    agentFiles
    commandFiles
    promptFiles
    {
      "${root}/extensions/auto-compact-resume/index.ts".source = autoCompactResumeSource;
      "${root}/extensions/nix-gallery/index.ts".source = "${pkgs.pi-gallery}/share/pi-gallery/index.ts";
      "${root}/extensions/pi-mcp-adapter".source = "${extensionRoot}/pi-mcp-adapter";
      "${root}/extensions/pi-quiet".source = "${extensionRoot}/pi-quiet";
      "${root}/keybindings.json".source = json.generate "pi-${profile.id}-keybindings.json" keybindings;
      "${root}/model-router.json".source = json.generate "pi-${profile.id}-model-router.json" modelRouter;
      "${root}/models.json".source = json.generate "pi-${profile.id}-models.json" models;
      "${globalMcpPath}".source = json.generate "pi-${profile.id}-mcp.json" mcp;
    }
  ];

  companions = [ ];

  requiredEnvNames = lib.unique (
    lib.sort builtins.lessThan (
      [
        "CONTEXT7_API_KEY"
        "PERPLEXITY_API_KEY"
        "REF_API_KEY"
      ]
      ++ mcpRequiredEnvNames
      ++ providerRequiredEnvNames
    )
  );

  mutableMcpGuard = {
    path = ".pi/agent/mcp.json";
    forbiddenKeys = [
      "mcpServers"
      "imports"
    ];
  };
}
