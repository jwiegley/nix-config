{ lib, pkgs }:

{
  profile,
  selected,
  modelData,
  homeDirectory,
  xdgConfigHome,
}:

assert builtins.isAttrs modelData;
assert builtins.isString homeDirectory;
assert builtins.isString xdgConfigHome;

let
  inherit (profile) root;
  json = pkgs.formats.json { };
  mergeFiles = import ./merge-files.nix { inherit lib; };

  isTypedEnv =
    value:
    builtins.isAttrs value && builtins.attrNames value == [ "env" ] && builtins.isString value.env;
  providerRequiredEnvNames = lib.concatMap (
    provider: lib.optional (isTypedEnv provider.apiKey) provider.apiKey.env
  ) (builtins.attrValues modelData.providers);
  mcpRequiredEnvNames = lib.concatMap (
    server:
    lib.concatMap (value: lib.optional (isTypedEnv value) value.env) (
      builtins.attrValues (server.transport.env or { })
      ++ builtins.attrValues (server.transport.headers or { })
    )
  ) (builtins.attrValues selected.mcpServers);

  renderSecretReferences =
    value:
    if isTypedEnv value then
      "{env:${value.env}}"
    else if builtins.isAttrs value then
      lib.mapAttrs (_: renderSecretReferences) value
    else if builtins.isList value then
      map renderSecretReferences value
    else
      value;

  renderMcpServer =
    server:
    let
      transport = renderSecretReferences server.transport;
      native =
        if transport ? url then
          {
            type = "remote";
            inherit (transport) url;
          }
          // lib.optionalAttrs (transport ? headers) { inherit (transport) headers; }
        else
          {
            type = "local";
            command = [ transport.command ] ++ transport.args;
          }
          // lib.optionalAttrs (transport ? env) { environment = transport.env; };
    in
    lib.recursiveUpdate native (server.overrides.opencode or { });

  orderedValues =
    set: lib.sort (left: right: left.sourceOrder < right.sourceOrder) (builtins.attrValues set);

  renderModel =
    model:
    {
      name = model.displayName;
    }
    // lib.optionalAttrs (model ? contextLimit || model ? outputLimit) {
      limit =
        lib.optionalAttrs (model ? contextLimit) { context = model.contextLimit; }
        // lib.optionalAttrs (model ? outputLimit) { output = model.outputLimit; };
    };

  renderProvider = providerName: provider: {
    inherit (provider.opencode) name npm;
    options = {
      apiKey =
        if isTypedEnv provider.apiKey then "{env:${provider.apiKey.env}}" else provider.apiKey.nonSecret;
      baseURL = provider.baseUrl;
      inherit (provider.opencode) timeout;
    };
    models = lib.listToAttrs (
      map (model: lib.nameValuePair model.id (renderModel model)) (
        orderedValues (lib.filterAttrs (_: model: model.provider == providerName) modelData.models)
      )
    );
  };

  config = {
    "$schema" = "https://opencode.ai/config.json";
    disabled_providers = [
      "openai"
      "gemini"
      "anthropic"
    ];
    instructions = [
      "CLAUDE.md"
      "AGENTS.md"
    ];
    mcp = lib.mapAttrs (_: renderMcpServer) selected.mcpServers;
    provider = lib.mapAttrs renderProvider modelData.providers;
  }
  // lib.optionalAttrs (modelData ? default) {
    model = "${modelData.default.provider}/${modelData.default.model}";
    small_model = "${modelData.default.provider}/${modelData.default.model}";
  };

  openCodeBuiltinTools = [
    "bash"
    "edit"
    "glob"
    "grep"
    "list"
    "lsp"
    "patch"
    "question"
    "read"
    "skill"
    "task"
    "todoread"
    "todowrite"
    "webfetch"
    "websearch"
    "write"
  ];

  normalizeTool =
    tool:
    let
      call = builtins.match "([^()]*)[(].*" tool;
      bare = if call == null then tool else builtins.head call;
      withoutMcp = lib.removePrefix "mcp__" bare;
    in
    lib.toLower (lib.replaceStrings [ "__" ] [ "_" ] withoutMcp);

  renderAgentMetadata =
    item:
    let
      declared =
        if !(item.metadata ? tools) then
          [ ]
        else if builtins.isList item.metadata.tools then
          item.metadata.tools
        else
          lib.splitString ", " item.metadata.tools;
      enabled = map normalizeTool declared;
      toolNames = lib.unique (lib.sort builtins.lessThan (openCodeBuiltinTools ++ enabled));
    in
    builtins.removeAttrs item.metadata [ "tools" ]
    // lib.optionalAttrs (item.metadata ? tools) {
      tools = lib.genAttrs toolNames (name: builtins.elem name enabled);
    };

  renderMarkdown =
    metadata: source:
    if metadata == { } then
      builtins.readFile source
    else
      "---\n${builtins.toJSON metadata}\n---\n${builtins.readFile source}";

  agents = lib.mapAttrs' (
    name: item:
    lib.nameValuePair "${root}/agents/${name}.md" {
      text = renderMarkdown (renderAgentMetadata item) item.source;
    }
  ) selected.agents;
  commands = lib.mapAttrs' (
    name: item:
    lib.nameValuePair "${root}/commands/${name}.md" {
      text = renderMarkdown item.metadata item.source;
    }
  ) selected.commands;
  skills = lib.mapAttrs' (
    name: item:
    lib.nameValuePair "${root}/skills/${name}" {
      inherit (item) source;
    }
  ) selected.skills;
  prompts = lib.mapAttrs' (
    name: item:
    lib.nameValuePair "${root}/commands/${name}.md" {
      inherit (item) source;
    }
  ) selected.prompts;
in
{
  files = mergeFiles [
    agents
    commands
    skills
    prompts
    {
      "${root}/opencode.json".source = json.generate "opencode-${profile.id}.json" config;
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
}
