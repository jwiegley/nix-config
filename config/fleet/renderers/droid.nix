{ lib, pkgs }:

{
  profile,
  selected,
  modelData,
  homeDirectory,
  xdgConfigHome,
}:

assert builtins.isAttrs modelData;
assert builtins.all (provider: provider ? droid && provider.droid ? providerType) (
  builtins.attrValues modelData.providers
);
assert builtins.isString homeDirectory;
assert builtins.isString xdgConfigHome;

let
  inherit (profile) root;
  json = pkgs.formats.json { };
  mergeFiles = import ./merge-files.nix { inherit lib; };

  isTypedEnv = value: builtins.isAttrs value && builtins.attrNames value == [ "env" ];
  providerRequiredEnvNames = lib.concatMap (
    provider: lib.optional (isTypedEnv provider.apiKey) provider.apiKey.env
  ) (builtins.attrValues modelData.providers);
  renderCredential =
    credential:
    if isTypedEnv credential then
      "$" + "{" + credential.env + "}"
    else if builtins.isAttrs credential && builtins.attrNames credential == [ "nonSecret" ] then
      credential.nonSecret
    else
      throw "unsupported Droid credential shape";

  orderedValues =
    set: lib.sort (left: right: left.sourceOrder < right.sourceOrder) (builtins.attrValues set);
  renderModel =
    index: model:
    let
      provider = modelData.providers.${model.provider};
      displayName = "[${provider.displayName}] ${model.displayName}";
    in
    {
      apiKey = renderCredential provider.apiKey;
      inherit (provider) baseUrl;
      inherit displayName index;
      id = "custom:${lib.replaceStrings [ " " ] [ "-" ] displayName}-${toString index}";
      model = model.id;
      noImageSupport = provider.droid.noImageSupport or false;
      provider = provider.droid.providerType;
    }
    // lib.optionalAttrs (model ? maxOutputTokens) {
      inherit (model) maxOutputTokens;
    }
    // lib.optionalAttrs (provider.droid ? extraArgs) {
      inherit (provider.droid) extraArgs;
    }
    // lib.optionalAttrs (provider.droid ? extraHeaders) {
      inherit (provider.droid) extraHeaders;
    };
  settings = {
    customModels = lib.imap0 renderModel (orderedValues modelData.models);
  };

  renderMcpServer =
    name: server:
    let
      inherit (server) transport;
      literalEnv = lib.filterAttrs (_: value: !isTypedEnv value) (transport.env or { });
    in
    if transport ? url && transport ? headers then
      assert builtins.elem name [
        "Ref"
        "context7"
      ];
      assert builtins.length (builtins.attrNames transport.headers) == 1;
      let
        headerName = builtins.head (builtins.attrNames transport.headers);
        credential = transport.headers.${headerName};
      in
      assert isTypedEnv credential;
      {
        type = "stdio";
        disabled = false;
        command = "agent-http-header-bridge";
        args = [
          transport.url
          headerName
          credential.env
        ];
      }
    else if transport ? url then
      assert !(transport ? headers);
      {
        type = "http";
        disabled = false;
        inherit (transport) url;
      }
    else
      {
        type = "stdio";
        disabled = false;
        inherit (transport) command args;
      }
      // lib.optionalAttrs (literalEnv != { }) { env = literalEnv; };
  mcp = {
    mcpServers = lib.mapAttrs renderMcpServer selected.mcpServers;
  };

  renderMarkdown =
    item:
    if item.metadata == { } then
      builtins.readFile item.source
    else
      "---\n${builtins.toJSON item.metadata}\n---\n${builtins.readFile item.source}";
  skillDirectory = item: pkgs.writeTextDir "SKILL.md" (renderMarkdown item);

  agents = lib.mapAttrs' (
    name: item:
    lib.nameValuePair "${root}/droids/${name}.md" {
      text = renderMarkdown item;
    }
  ) selected.agents;
  skills = lib.mapAttrs' (
    name: item:
    lib.nameValuePair "${root}/skills/${name}" {
      inherit (item) source;
    }
  ) selected.skills;
  commands = lib.mapAttrs' (
    name: item:
    lib.nameValuePair "${root}/skills/${name}" {
      source = skillDirectory item;
    }
  ) selected.commands;
  prompts = lib.mapAttrs' (
    name: item:
    lib.nameValuePair "${root}/skills/${name}" {
      source = pkgs.writeTextDir "SKILL.md" (builtins.readFile item.source);
    }
  ) selected.prompts;
in
{
  files = mergeFiles [
    agents
    skills
    commands
    prompts
    {
      "${root}/nix-managed-settings.json".source =
        json.generate "droid-${profile.id}-nix-managed-settings.json" settings;
      "${root}/mcp.json".source = json.generate "droid-${profile.id}-mcp.json" mcp;
    }
  ];

  companions = [
    "${root}/nix-managed-settings.json"
    "${root}/mcp.json"
  ];
  requiredEnvNames = lib.unique (
    lib.sort builtins.lessThan (
      [
        "ANTHROPIC_API_KEY"
        "CONTEXT7_API_KEY"
        "GEMINI_API_KEY"
        "OPENAI_API_KEY"
        "PERPLEXITY_API_KEY"
        "REF_API_KEY"
      ]
      ++ providerRequiredEnvNames
    )
  );
}
