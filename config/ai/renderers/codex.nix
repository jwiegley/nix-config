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
  json = pkgs.formats.json { };
  toml = pkgs.formats.toml { };
  mergeFiles = import ./merge-files.nix { inherit lib; };

  sortedNames = set: lib.sort builtins.lessThan (builtins.attrNames set);

  litellmSolId = "positron_openai/gpt-5.6-sol";
  solModels = lib.filterAttrs (
    _: model: model.provider == "positron-openai" && model.id == "gpt-5.6-sol"
  ) modelData.models;
  solModel =
    assert builtins.length (builtins.attrValues solModels) == 1;
    assert (builtins.head (builtins.attrValues solModels)).contextLimit == 1050000;
    builtins.head (builtins.attrValues solModels);

  codexSourceCatalog = builtins.fromJSON (
    builtins.readFile "${pkgs.codex.src}/codex-rs/models-manager/models.json"
  );
  sourceSolModel = lib.findFirst (
    model: model.slug == "gpt-5.6-sol"
  ) (throw "Codex source catalog does not contain gpt-5.6-sol") codexSourceCatalog.models;
  patchSolModel =
    model:
    model
    // {
      context_window = solModel.contextLimit;
      max_context_window = solModel.contextLimit;
      effective_context_window_percent = 95;
    };
  managedModelCatalog = {
    models =
      map (
        model: if model.slug == "gpt-5.6-sol" then patchSolModel model else model
      ) codexSourceCatalog.models
      ++ [
        (
          (patchSolModel sourceSolModel)
          // {
            slug = litellmSolId;
            display_name = "${solModel.displayName} via LiteLLM";
          }
        )
      ];
  };
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
    model_catalog_json = "${homeDirectory}/${profile.root}/nix-managed-model-catalog.json";
    model_context_window = solModel.contextLimit;
    model_auto_compact_token_limit = 900000;
    notify = lib.concatMap (item: item.codex.notify or [ ]) hookItems;
    mcp_servers = lib.mapAttrs (_: renderMcpServer) selected.mcpServers;
  };
  managedHooks = {
    hooks = lib.zipAttrsWith (_: bodies: lib.concatLists bodies) (
      map (item: item.hooks or { }) hookItems
    );
  };

  projectionText =
    kind: name: metadata: source:
    "---\n${builtins.toJSON metadata}\n---\n"
    + "Use this skill for the promptdeploy ${kind} '${name}'.\n\n"
    + "Treat the user's current request as the arguments for the prompt below. "
    + "If the prompt contains `$ARGUMENTS`, interpret it as those arguments.\n\n"
    + "Prompt:\n\n"
    + builtins.readFile source;

  explicitOnlyPolicy = pkgs.writeTextDir "agents/openai.yaml" ''
    policy:
      allow_implicit_invocation: false
  '';

  mkProjection =
    kind: name: metadata: source:
    pkgs.symlinkJoin {
      name = "codex-${kind}-${name}";
      paths = [
        (pkgs.writeTextDir "SKILL.md" (projectionText kind name metadata source))
        explicitOnlyPolicy
      ];
    };

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

  codexPrompts = lib.filterAttrs (name: _: !(lib.hasPrefix "bigpowers-" name)) selected.prompts;
  promptFiles = lib.mapAttrs' (
    name: item:
    lib.nameValuePair ".agents/skills/prompt-${name}" {
      source = mkProjection "prompt" name {
        name = "prompt-${name}";
        description = "Promptdeploy rendered prompt '${name}'.";
      } item.source;
    }
  ) codexPrompts;

  managedPath = "${profile.root}/nix-managed.config.toml";
  hooksPath = "${profile.root}/hooks.json";
in
{
  files = mergeFiles [
    agentFiles
    skillFiles
    commandFiles
    promptFiles
    {
      "${hooksPath}".source = json.generate "codex-hooks.json" managedHooks;
      "${managedPath}".source = toml.generate "codex-nix-managed.config.toml" managedConfig;
      "${profile.root}/nix-managed-model-catalog.json".source =
        json.generate "codex-nix-managed-model-catalog.json" managedModelCatalog;
    }
  ];

  companions = [
    hooksPath
    managedPath
    "${profile.root}/nix-managed-model-catalog.json"
  ];
  requiredEnvNames = [
    "CONTEXT7_API_KEY"
    "PERPLEXITY_API_KEY"
    "REF_API_KEY"
  ];
}
