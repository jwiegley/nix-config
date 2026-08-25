{ lib, pkgs }:

{
  profile,
  selected,
  homeDirectory,
  xdgConfigHome,
  localModelEndpoints,
  caBundle,
}:

let
  model = "DeepSeek-V4-Flash-0731-oQ8e-mtp";
  baseUrl = "http://localhost:8000/v1";
  apiKey = "\${OPENAI_API_KEY}";
  managedStdio = import ../managed-stdio.nix { inherit lib; };
  renderManagedStdio = managedStdio.render pkgs;
  renderLib = import ./render-lib.nix { inherit lib; };

  localEndpoint = {
    provider = "custom";
    base_url = baseUrl;
    api_key = apiKey;
    api_mode = "chat_completions";
  };
  localRoute = localEndpoint // {
    inherit model;
  };
  auxiliaryTasks = [
    "approval"
    "background_review"
    "compression"
    "curator"
    "goal_judge"
    "kanban_decomposer"
    "mcp"
    "memory_query_rewrite"
    "moa_aggregator"
    "moa_reference"
    "monitor"
    "profile_describer"
    "skills_hub"
    "title_generation"
    "triage_specifier"
    "tts_audio_tags"
    "vision"
    "web_extract"
  ];
  auxiliary = lib.genAttrs auxiliaryTasks (_: localRoute) // {
    free_only = true;
    openrouter_model = "";
    stream_only_base_urls = [ ];
    transient_retries = 2;
  };

  renderEnvironment =
    environment:
    lib.mapAttrs (
      _: value:
      lib.replaceStrings
        [
          "\${HOME}"
          "\${SSL_CERT_FILE}"
        ]
        [
          homeDirectory
          caBundle
        ]
        value
    ) (lib.filterAttrs (_: value: !renderLib.isTypedEnv value) environment);
  renderMcpServer =
    _: server:
    let
      transport = renderManagedStdio server.transport;
    in
    {
      enabled = true;
      inherit (transport) command args;
    }
    // lib.optionalAttrs ((transport.env or { }) != { }) {
      env = renderEnvironment (transport.env or { });
    }
    // lib.optionalAttrs (server ? tools) { inherit (server) tools; };
  mcpServers = lib.mapAttrs renderMcpServer selected.mcpServers;

  qdrantPlugin = pkgs.hermes-qdrant-memory;
  qdrantPluginDirectoryName = qdrantPlugin.hermesPluginDirectoryName;
  hermesConfig = {
    model = localEndpoint // {
      default = model;
      context_length = 262144;
    };
    providers = { };
    fallback_providers = [ ];
    toolsets = [ "hermes-cli" ];
    agent = {
      gateway_timeout = 0;
      max_turns = null;
    };
    terminal = {
      backend = "local";
      cwd = homeDirectory;
      home_mode = "real";
    };
    approvals = {
      mode = "off";
      cron_mode = "approve";
      single_query_mode = "approve";
      deny = [ ];
      mcp_reload_confirm = false;
      destructive_slash_confirm = false;
    };
    web = {
      search_backend = "searxng";
      extract_backend = "local";
      keyless_fallback = false;
      keyless_rescue = false;
    };
    memory.provider = qdrantPluginDirectoryName;
    plugins = {
      enabled = [ "web-local-extract" ];
      qdrant = {
        collection = "assistant";
        connection.url = "https://qdrant.vulcan.lan";
        embedding = {
          model = "bge-m3-mlx-fp16";
          dimension = 1024;
          base_url = baseUrl;
        };
      };
    };
    delegation = localRoute // {
      subagent_auto_approve = true;
    };
    moa = {
      default_preset = "default";
      presets.default = {
        enabled = true;
        max_tokens = 4096;
        reference_models = [
          {
            provider = "custom";
            inherit model;
            enabled = true;
          }
        ];
        aggregator = {
          provider = "custom";
          inherit model;
        };
      };
    };
    inherit auxiliary;
    mcp_servers = mcpServers;
  };
  hermesServiceOptions = {
    enable = true;
    installPackage = true;
    gateway.enable = true;
    backend.mode = "none";
    hermesHome = "${homeDirectory}/.hermes";
    workingDirectory = homeDirectory;
    configFile = pkgs.writeText "${profile.id}-config.yaml" (builtins.toJSON hermesConfig);
    settings = { };
    mcpServers = { };
    environment = {
      API_SERVER_ENABLED = "true";
      API_SERVER_HOST = "127.0.0.1";
      API_SERVER_MODEL_NAME = model;
      API_SERVER_PORT = "8642";
      HERMES_CA_BUNDLE = caBundle;
      SEARXNG_URL = "https://searxng.vulcan.lan";
      SSL_CERT_FILE = caBundle;
    };
    environmentFiles = [ ];
    extraPlugins = [
      pkgs.hermes-local-extract
      qdrantPlugin
    ];
    extraPythonPackages = [ ];
    extraDependencyGroups = [ ];
  };
in
assert profile.id == "hera-hermes";
assert profile.client == "hermes";
assert profile.root == ".hermes";
assert profile.host == "hera";
assert profile.platform == "darwin";
assert profile.audiences == [ "personal" ];
assert profile.localModelRoutes;
assert !profile.hermesRoute;
assert homeDirectory == "/Users/johnw";
assert xdgConfigHome == "${homeDirectory}/.config";
assert localModelEndpoints.omlx == baseUrl;
assert builtins.isString caBundle && lib.hasPrefix "/" caBundle;
assert selected.agents == { };
assert selected.commands == { };
assert selected.skills == { };
assert selected.prompts == { };
assert selected.hooks == { };
assert selected.marketplaces == { };
assert selected.settings == { };
assert
  builtins.attrNames selected.mcpServers == [
    "org-db"
    "stock-trader"
  ];
assert builtins.hasAttr "hermes-local-extract" pkgs;
assert builtins.hasAttr "hermes-org-db-mcp" pkgs;
assert builtins.hasAttr "hermes-qdrant-memory" pkgs;
assert builtins.hasAttr "nix-managed-mcp-stdio" pkgs;
assert qdrantPluginDirectoryName == "nix-managed-hermes-qdrant-memory";
{
  files = { };
  inherit hermesConfig hermesServiceOptions;
}
