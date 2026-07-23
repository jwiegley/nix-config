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
  toml = pkgs.formats.toml { };
  mergeFiles = import ./merge-files.nix { inherit lib; };

  sortedNames = set: lib.sort builtins.lessThan (builtins.attrNames set);

  isTypedEnv =
    value:
    builtins.isAttrs value && builtins.attrNames value == [ "env" ] && builtins.isString value.env;

  renderMcpServer =
    server:
    let
      inherit (server) transport;
      typedEnv = lib.filterAttrs (_: isTypedEnv) (transport.env or { });
      literalEnv = lib.filterAttrs (_: value: !isTypedEnv value) (transport.env or { });
      native =
        if transport ? url then
          {
            inherit (transport) url;
          }
          // lib.optionalAttrs (transport ? headers) {
            env_http_headers = lib.mapAttrs (_: reference: reference.env) transport.headers;
          }
        else
          {
            inherit (transport) command args;
          }
          // lib.optionalAttrs (literalEnv != { }) { env = literalEnv; }
          // lib.optionalAttrs (typedEnv != { }) {
            env_vars = map (name: typedEnv.${name}.env) (sortedNames typedEnv);
          };
    in
    lib.recursiveUpdate native (server.overrides.codex or { });

  hookItems = builtins.attrValues selected.hooks;
  managedConfig = {
    notify = lib.concatMap (item: item.codex.notify or [ ]) hookItems;
    hooks = lib.zipAttrsWith (_: bodies: lib.concatLists bodies) (
      map (item: item.hooks or { }) hookItems
    );
    mcp_servers = lib.mapAttrs (_: renderMcpServer) selected.mcpServers;
  };

  projectionText =
    kind: name: metadata: source:
    "---\n${builtins.toJSON metadata}\n---\n"
    + "Use this skill for the promptdeploy ${kind} '${name}'.\n\n"
    + "Treat the user's current request as the arguments for the prompt below. "
    + "If the prompt contains `$ARGUMENTS`, interpret it as those arguments.\n\n"
    + "Prompt:\n\n"
    + builtins.readFile source;

  mkProjection =
    kind: name: metadata: source:
    pkgs.writeTextDir "SKILL.md" (projectionText kind name metadata source);

  agentFiles = lib.mapAttrs' (
    name: item:
    lib.nameValuePair "${profile.root}/agents/${name}.toml" {
      source = toml.generate "codex-agent-${name}.toml" (
        builtins.removeAttrs item.metadata [ "tools" ]
        // {
          developer_instructions = builtins.readFile item.source;
        }
      );
    }
  ) selected.agents;

  skillFiles = lib.mapAttrs' (
    name: item: lib.nameValuePair ".agents/skills/${name}" { inherit (item) source; }
  ) selected.skills;

  commandFiles = lib.mapAttrs' (
    name: item:
    lib.nameValuePair ".agents/skills/command-${name}" {
      source = mkProjection "command" name {
        name = "command-${name}";
        description = item.metadata.description or "Promptdeploy command '${name}'.";
      } item.source;
    }
  ) selected.commands;

  promptFiles = lib.mapAttrs' (
    name: item:
    lib.nameValuePair ".agents/skills/prompt-${name}" {
      source = mkProjection "prompt" name {
        name = "prompt-${name}";
        description = "Promptdeploy rendered prompt '${name}'.";
      } item.source;
    }
  ) selected.prompts;

  managedPath = "${profile.root}/nix-managed.config.toml";
in
{
  files = mergeFiles [
    agentFiles
    skillFiles
    commandFiles
    promptFiles
    {
      "${managedPath}".source = toml.generate "codex-nix-managed.config.toml" managedConfig;
    }
  ];

  companions = [ managedPath ];

  requiredEnvNames = [
    "CONTEXT7_API_KEY"
    "PERPLEXITY_API_KEY"
    "REF_API_KEY"
  ];
}
