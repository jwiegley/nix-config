{
  lib,
  pkgs,
  llmAgents,
}:

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

  system = pkgs.stdenv.hostPlatform.system;
  codexSourceCatalog = "${
    llmAgents.packages.${system}.codex.src
  }/codex-rs/models-manager/models.json";
  codexSourceCatalogData = builtins.fromJSON (builtins.readFile codexSourceCatalog);
  nativeSolModels = builtins.filter (
    model: model.slug == "gpt-5.6-sol"
  ) codexSourceCatalogData.models;
  nativeSol =
    assert builtins.length nativeSolModels == 1;
    builtins.head nativeSolModels;
  nativeSolAutoCompactTokenLimit =
    assert builtins.isInt nativeSol.context_window;
    builtins.div (nativeSol.context_window * 4) 5;
  managedModelCatalog = pkgs.runCommand "codex-nix-managed-model-catalog.json" { } ''
    cp ${codexSourceCatalog} "$out"
  '';
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
  localConfig = lib.optionalAttrs (profile.host == "hera") {
    model_providers = {
      omlx = {
        name = "oMLX";
        base_url = modelData.providers.omlx.baseUrl;
        env_key = "OMLX_API_KEY";
        wire_api = "responses";
      };
      llama-swap = {
        name = "llama-swap";
        base_url = modelData.providers.llama-cpp-local.baseUrl;
        env_key = "LLAMA_SWAP_API_KEY";
        wire_api = "responses";
      };
    };
    profiles = {
      omlx = {
        model = "Qwen3.6-27B-oQ4e-mtp";
        model_provider = "omlx";
      };
      llama-swap = {
        model = "GLM-5.2";
        model_provider = "llama-swap";
      };
    };
  };
  managedConfig = {
    model = "gpt-5.6-sol";
    model_auto_compact_token_limit = nativeSolAutoCompactTokenLimit;
    model_catalog_json = "${homeDirectory}/${profile.root}/nix-managed-model-catalog.json";
    model_reasoning_effort = "ultra";
    notify = lib.concatMap (item: item.codex.notify or [ ]) hookItems;
    mcp_servers = lib.mapAttrs (_: renderMcpServer) selected.mcpServers;
    shell_environment_policy = {
      ignore_default_excludes = false;
      exclude = [ "REF_API_KEY" ];
    };
  }
  // localConfig;
  managedHooks = {
    hooks = lib.zipAttrsWith (_: bodies: lib.concatLists bodies) (
      map (item: item.hooks or { }) hookItems
    );
  };

  projectionText =
    kind: name: metadata: source:
    "---\n"
    + "name: ${builtins.toJSON metadata.name}\n"
    + "description: ${builtins.toJSON metadata.description}\n"
    + "---\n"
    + "Use this skill for the managed ${kind} '${name}'.\n\n"
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
    let
      manifest = pkgs.writeText "codex-${kind}-${name}-SKILL.md" (
        projectionText kind name metadata source
      );
    in
    pkgs.runCommandLocal "codex-${kind}-${name}" { } ''
      install -Dm0444 ${manifest} "$out/SKILL.md"
      install -Dm0444 ${explicitOnlyPolicy}/agents/openai.yaml "$out/agents/openai.yaml"
    '';

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
        description = item.metadata.description or "Managed command '${name}'.";
      } item.source;
    }
  ) selected.commands;

  promptFiles = lib.mapAttrs' (
    name: item:
    lib.nameValuePair ".agents/skills/prompt-${name}" {
      source = mkProjection "prompt" name {
        name = "prompt-${name}";
        description = "Managed prompt '${name}'.";
      } item.source;
    }
  ) selected.prompts;

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
      "${profile.root}/nix-managed-model-catalog.json".source = managedModelCatalog;
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
