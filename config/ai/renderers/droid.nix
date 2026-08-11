{ lib, pkgs }:

{
  profile,
  selected,
  homeDirectory,
  xdgConfigHome,
}:

# The renderer contract supplies these uniformly; assert them even though
# this client's documents do not embed them, both to validate the interface
# and because the portable lint gate (bare `deadnix --fail`) rejects unused
# lambda patterns.
assert builtins.isString homeDirectory;
assert builtins.isString xdgConfigHome;

let
  inherit (profile) root;
  json = pkgs.formats.json { };
  mergeFiles = import ./merge-files.nix { inherit lib; };

  renderLib = import ./render-lib.nix { inherit lib; };
  inherit (renderLib) isTypedEnv;

  renderMcpServer =
    _: server:
    let
      inherit (server) transport;
      literalEnv = lib.filterAttrs (_: value: !isTypedEnv value) (transport.env or { });
    in
    if transport ? url then
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

  droidAgentCapabilities = [
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
      output = "Execute";
    }
  ];
  renderAgentMetadata =
    metadata:
    builtins.removeAttrs metadata [ "capabilities" ]
    // lib.optionalAttrs (metadata ? capabilities) {
      tools = renderLib.renderAgentCapabilities droidAgentCapabilities metadata.capabilities;
    };
  renderMarkdown = item: renderLib.renderMarkdownFile item.metadata item.source;
  renderAgent = item: renderLib.renderMarkdownFile (renderAgentMetadata item.metadata) item.source;
  skillDirectory = item: pkgs.writeTextDir "SKILL.md" (renderMarkdown item);

  agents = lib.mapAttrs' (
    name: item:
    lib.nameValuePair "${root}/droids/${name}.md" {
      text = renderAgent item;
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
      "${root}/mcp.json".source = json.generate "droid-${profile.id}-mcp.json" mcp;
    }
  ];
}
