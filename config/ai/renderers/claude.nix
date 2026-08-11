{ lib, pkgs }:

{
  profile,
  selected,
  homeDirectory,
  xdgConfigHome,
}:

assert builtins.isString homeDirectory;
assert builtins.isString xdgConfigHome;

let
  inherit (profile) root;
  json = pkgs.formats.json { };
  mergeFiles = import ./merge-files.nix { inherit lib; };

  renderLib = import ./render-lib.nix { inherit lib; };
  renderMarkdown = item: renderLib.renderMarkdownFile item.metadata item.source;
  claudeAgentCapabilities = [
    {
      capability = "read-files";
      output = "Read";
    }
    {
      capability = "search-text";
      output = "Grep";
    }
    {
      capability = "find-files";
      output = "Glob";
    }
    {
      capability = "run-commands";
      output = "Bash";
    }
  ];
  renderAgentMetadata =
    metadata:
    builtins.removeAttrs metadata [ "capabilities" ]
    // lib.optionalAttrs (metadata ? capabilities) {
      tools = lib.concatStringsSep ", " (
        renderLib.renderAgentCapabilities claudeAgentCapabilities metadata.capabilities
      );
    };
  renderAgent = item: renderLib.renderMarkdownFile (renderAgentMetadata item.metadata) item.source;

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

  settingsItems = builtins.attrValues selected.settings;
  statusLineCommands = map (item: item.statusLineCommand) (
    lib.filter (item: item ? statusLineCommand) settingsItems
  );
  statusLineCommand =
    assert builtins.length statusLineCommands == 1;
    builtins.head statusLineCommands;
  settings = lib.foldl' lib.recursiveUpdate { } (map (item: item.base or { }) settingsItems) // {
    statusLine = {
      type = "command";
      command =
        "${statusLineCommand.executable} "
        + "${homeDirectory}/${root}/${statusLineCommand.rootRelativePath}";
    };
    inherit hooks extraKnownMarketplaces enabledPlugins;
  };

  renderSecretReferences =
    value:
    if renderLib.isTypedEnv value then
      "$" + "{" + value.env + "}"
    else if builtins.isAttrs value && builtins.attrNames value == [ "env" ] then
      throw "claude renderer: malformed environment reference (single `env` attribute that is not an uppercase variable name)"
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
      text = renderAgent item;
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
}
