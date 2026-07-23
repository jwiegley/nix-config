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

  expectedProviderNames = [
    "litellm"
    "llama-cpp-local"
    "nvidia"
    "omlx"
    "positron-anthropic"
    "positron-google"
    "positron-openai"
  ];
  expectedMcpNames = [
    "Ref"
    "anvil"
    "context-hub"
    "context7"
    "perplexity"
    "sequential-thinking"
  ];
  providerApis = {
    litellm = "openai-completions";
    llama-cpp-local = "openai-completions";
    nvidia = "openai-completions";
    omlx = "openai-completions";
    positron-anthropic = "anthropic-messages";
    positron-google = "google-generative-ai";
    positron-openai = "openai-responses";
  };
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
  isNonSecret =
    value:
    builtins.isAttrs value
    && builtins.attrNames value == [ "nonSecret" ]
    && builtins.isString value.nonSecret;
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
    provider: lib.optional (isTypedEnv provider.apiKey) provider.apiKey.env
  ) (builtins.attrValues modelData.providers);
  renderEnv = name: "$" + "{" + name + "}";
  renderCredential =
    value:
    if isTypedEnv value then
      renderEnv value.env
    else if isNonSecret value then
      value.nonSecret
    else
      throw "unsupported Pi credential shape";

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
  renderProvider = providerName: provider: {
    api = providerApis.${providerName};
    apiKey = renderCredential provider.apiKey;
    inherit (provider) baseUrl;
    models = map renderModel (
      orderedValues (lib.filterAttrs (_: model: model.provider == providerName) modelData.models)
    );
  };
  models = {
    providers = lib.mapAttrs renderProvider modelData.providers;
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
      assert builtins.hasAttr name expectedHttpHeaders;
      assert hasOnlyKeys [
        "headers"
        "url"
      ] transport;
      assert isSafeUrl transport.url;
      assert builtins.attrNames transport.headers == [ expectedHttpHeaders.${name} ];
      assert isTypedEnv transport.headers.${expectedHttpHeaders.${name}};
      {
        inherit (transport) url;
        headers = lib.mapAttrs (_: reference: renderEnv reference.env) transport.headers;
        oauth = false;
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
assert builtins.length (builtins.attrNames selected.prompts) == 2;
assert builtins.length (builtins.attrNames selected.skills) == 38;
assert selected.hooks == { };
assert selected.marketplaces == { };
assert selected.settings == { };
assert builtins.attrNames selected.mcpServers == expectedMcpNames;
assert builtins.attrNames modelData.providers == expectedProviderNames;
assert !(modelData ? default);
assert builtins.all (model: builtins.hasAttr model.provider modelData.providers) (
  builtins.attrValues modelData.models
);
assert
  lib.intersectLists (builtins.attrNames selected.commands) (builtins.attrNames selected.prompts)
  == [ ];
assert builtins.hasAttr "agent-resources" pkgs;
{
  files = mergeFiles [
    agentFiles
    commandFiles
    promptFiles
    {
      "${root}/extensions/pi-mcp-adapter".source = "${extensionRoot}/pi-mcp-adapter";
      "${root}/extensions/pi-quiet".source = "${extensionRoot}/pi-quiet";
      "${root}/extensions/pi-subagent".source = "${extensionRoot}/pi-subagent";
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
