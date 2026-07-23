{ lib, pkgs }:

{
  profile,
  selected,
  modelData,
  homeDirectory,
  xdgConfigHome,
}:

assert builtins.isAttrs modelData;
assert builtins.isString xdgConfigHome;

let
  inherit (profile) root;
  json = pkgs.formats.json { };
  mergeFiles = import ./merge-files.nix { inherit lib; };

  renderMarkdown =
    item:
    if item.metadata == { } then
      builtins.readFile item.source
    else
      "---\n${builtins.toJSON item.metadata}\n---\n${builtins.readFile item.source}";

  stripSource =
    value:
    if builtins.isAttrs value then
      lib.mapAttrs (_: stripSource) (builtins.removeAttrs value [ "_source" ])
    else if builtins.isList value then
      map stripSource value
    else
      value;

  hooks = lib.zipAttrsWith (_: values: lib.concatLists values) (
    map (item: stripSource item.hooks) (lib.attrValues selected.hooks)
  );

  extraKnownMarketplaces = lib.mapAttrs (_: marketplace: { inherit (marketplace) source; }) (
    lib.filterAttrs (_: marketplace: marketplace ? source) selected.marketplaces
  );
  enabledPlugins = lib.listToAttrs (
    lib.concatMap (
      marketplaceName:
      lib.mapAttrsToList (
        pluginName: enabled: lib.nameValuePair "${pluginName}@${marketplaceName}" enabled
      ) selected.marketplaces.${marketplaceName}.plugins
    ) (builtins.attrNames selected.marketplaces)
  );

  settingsItem = selected.settings.settings;
  settings =
    builtins.removeAttrs settingsItem.base (settingsItem.intentionalDeletions.${profile.id} or [ ])
    // {
      statusLine = {
        type = "command";
        command =
          "${settingsItem.statusLineCommand.executable} "
          + "${homeDirectory}/${root}/${settingsItem.statusLineCommand.rootRelativePath}";
      };
      inherit hooks extraKnownMarketplaces enabledPlugins;
    };

  renderSecretReferences =
    value:
    if builtins.isAttrs value && builtins.attrNames value == [ "env" ] then
      "$" + "{" + value.env + "}"
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
            type = "http";
            inherit (transport) url;
          }
          // lib.optionalAttrs (transport ? headers) { inherit (transport) headers; }
        else
          {
            inherit (transport) command args;
          }
          // lib.optionalAttrs (transport ? env) { inherit (transport) env; };
    in
    lib.recursiveUpdate native (server.overrides.claude or { });
  mcp = {
    mcpServers = lib.mapAttrs (_: renderMcpServer) selected.mcpServers;
  };

  agents = lib.mapAttrs' (
    name: item:
    lib.nameValuePair "${root}/agents/${name}.md" {
      text = renderMarkdown item;
    }
  ) selected.agents;
  commands = lib.mapAttrs' (
    name: item:
    lib.nameValuePair "${root}/commands/${name}.md" {
      text = renderMarkdown item;
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
      "${root}/statusline-command.sh".source = ../statusline-command.sh;
      "${root}/nix-managed-settings.json".source =
        json.generate "claude-${profile.id}-nix-managed-settings.json" settings;
      "${root}/nix-managed-mcp.json".source =
        json.generate "claude-${profile.id}-nix-managed-mcp.json" mcp;
    }
  ];

  companions = [
    "${root}/nix-managed-settings.json"
    "${root}/nix-managed-mcp.json"
  ];
  requiredEnvNames = [
    "ANTHROPIC_API_KEY"
    "CONTEXT7_API_KEY"
    "GEMINI_API_KEY"
    "OPENAI_API_KEY"
    "PERPLEXITY_API_KEY"
    "REF_API_KEY"
  ];
}
