{
  lib,
  pkgs,
  runCommand,
}:

let
  catalog = import ../../config/ai/catalog.nix {
    inherit lib;
    resources = pkgs.agent-resources;
  };
  profile = catalog.profiles.hera-hermes;
  selected = lib.mapAttrs (_: items: catalog.select profile items) catalog.items;
  rendered = (import ../../config/ai/renderers/hermes.nix { inherit lib pkgs; }) {
    inherit profile selected;
    homeDirectory = "/Users/johnw";
    xdgConfigHome = "/Users/johnw/.config";
    localModelEndpoints = catalog.localModelEndpointsByHost.hera;
    caBundle = "/managed-ca";
  };
  config = rendered.hermesConfig;
  service = rendered.hermesServiceOptions;
  model = "DeepSeek-V4-Flash-0731-oQ8e-mtp";
  baseUrl = "http://localhost:8000/v1";
  localRoute = {
    provider = "custom";
    inherit model;
    base_url = baseUrl;
    api_key = "\${OPENAI_API_KEY}";
    api_mode = "chat_completions";
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
  stockTools = [
    "get_quote"
    "get_price_history"
    "get_technical_analysis"
    "get_news_sentiment"
    "check_data_source_status"
    "scan_market"
    "analyze_options"
    "assess_trade_risk"
    "get_av_news_sentiment"
    "get_forex_rate"
    "get_crypto_quote"
    "get_commodity"
    "get_insider_transactions"
    "get_etf_profile"
    "get_earnings_calendar"
    "get_ipo_calendar"
    "get_listing_status"
    "get_historical_options"
  ];
  heraProfiles = builtins.attrValues (
    lib.filterAttrs (_: value: value.host == "hera") catalog.profiles
  );
  withoutHermes = builtins.filter (value: value.client != "hermes") heraProfiles;
  sharedMcpWithHermes = catalog.sharedMcpRegistryFor { profiles = heraProfiles; };
  sharedMcpWithoutHermes = catalog.sharedMcpRegistryFor { profiles = withoutHermes; };
  sharedSkillsWithHermes = catalog.sharedSkillsFor heraProfiles;
  sharedSkillsWithoutHermes = catalog.sharedSkillsFor withoutHermes;
  orgDb = config.mcp_servers.org-db;
  stockTrader = config.mcp_servers.stock-trader;
  serialized = builtins.toJSON config;
  reject = value: !(builtins.tryEval value).success;
  withStockTools =
    tools:
    catalog.items
    // {
      mcpServers = catalog.items.mcpServers // {
        stock-trader = catalog.items.mcpServers.stock-trader // {
          inherit tools;
        };
      };
    };
in
assert catalog.validate { };
assert
  catalog.contentClients == [
    "claude"
    "codex"
    "droid"
    "pi"
    "prime"
  ];
assert
  profile == {
    id = "hera-hermes";
    client = "hermes";
    host = "hera";
    platform = "darwin";
    root = ".hermes";
    audiences = [ "personal" ];
    localModelRoutes = true;
    hermesRoute = false;
  };
assert
  builtins.attrNames selected.mcpServers == [
    "org-db"
    "stock-trader"
  ];
assert selected.agents == { };
assert selected.commands == { };
assert selected.skills == { };
assert selected.prompts == { };
assert selected.hooks == { };
assert selected.marketplaces == { };
assert selected.settings == { };
assert sharedMcpWithHermes == sharedMcpWithoutHermes;
assert sharedSkillsWithHermes == sharedSkillsWithoutHermes;
assert rendered.files == { };
assert
  builtins.attrNames config == [
    "agent"
    "approvals"
    "auxiliary"
    "delegation"
    "fallback_providers"
    "mcp_servers"
    "memory"
    "moa"
    "model"
    "plugins"
    "providers"
    "terminal"
    "toolsets"
    "web"
  ];
assert
  config.model == (
    (builtins.removeAttrs localRoute [ "model" ])
    // {
      default = model;
      context_length = 262144;
    }
  );
assert config.providers == { };
assert config.fallback_providers == [ ];
assert
  builtins.attrNames (
    builtins.removeAttrs config.auxiliary [
      "free_only"
      "openrouter_model"
      "stream_only_base_urls"
      "transient_retries"
    ]
  ) == auxiliaryTasks;
assert builtins.all (task: config.auxiliary.${task} == localRoute) auxiliaryTasks;
assert config.auxiliary.free_only;
assert config.auxiliary.openrouter_model == "";
assert config.delegation == (localRoute // { subagent_auto_approve = true; });
assert
  config.moa == {
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
assert
  config.approvals == {
    mode = "off";
    cron_mode = "approve";
    single_query_mode = "approve";
    deny = [ ];
    mcp_reload_confirm = false;
    destructive_slash_confirm = false;
  };
assert
  config.web == {
    search_backend = "searxng";
    extract_backend = "local";
    keyless_fallback = false;
    keyless_rescue = false;
  };
assert config.memory.provider == pkgs.hermes-qdrant-memory.hermesPluginDirectoryName;
assert
  config.plugins == {
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
assert !lib.hasInfix ''"provider":"openrouter"'' serialized;
assert !lib.hasInfix ''"provider":"anthropic"'' serialized;
assert !lib.hasInfix ''"provider":"nous"'' serialized;
assert !lib.hasInfix ''"provider":"auto"'' serialized;
assert orgDb.command == "${pkgs.nix-managed-mcp-stdio}/bin/nix-managed-mcp-stdio";
assert lib.hasSuffix "/bin/org-db-mcp" (lib.last orgDb.args);
assert builtins.elem "PGPASSWORD" orgDb.args;
assert !(orgDb.env ? PGPASSWORD);
assert
  orgDb.env == {
    ORG_CONFIG = "/Users/johnw/.config/org/config.yaml";
    ORG_DB_BASE_URL = "http://127.0.0.1:8000";
    ORG_DB_MODEL = "bge-m3-mlx-fp16";
    PGDATABASE = "org";
    PGHOST = "vulcan.lan";
    PGPORT = "5432";
    PGSSLMODE = "verify-full";
    PGSSLROOTCERT = "/managed-ca";
    PGUSER = "openclaw";
  };
assert
  orgDb.tools.include == [
    "org_sql"
    "org_search"
  ];
assert stockTrader.tools.include == stockTools;
assert stockTrader.command == "${pkgs.nix-managed-mcp-stdio}/bin/nix-managed-mcp-stdio";
assert lib.last stockTrader.args == "/etc/profiles/per-user/johnw/bin/stock-trader-mcp";
assert builtins.all (tools: reject (catalog.validate { items = withStockTools tools; })) [
  { include = [ ]; }
  {
    include = [
      "get_quote"
      "get_quote"
    ];
  }
  { include = [ "../get_quote" ]; }
  {
    include = [ "get_quote" ];
    exclude = [ "get_quote" ];
  }
  { unknown = [ "get_quote" ]; }
];
assert service.settings == { };
assert service.mcpServers == { };
assert service.installPackage;
assert service.gateway.enable;
assert service.backend.mode == "none";
assert service.workingDirectory == "/Users/johnw";
assert service.hermesHome == "/Users/johnw/.hermes";
assert
  service.environment == {
    API_SERVER_ENABLED = "true";
    API_SERVER_HOST = "127.0.0.1";
    API_SERVER_MODEL_NAME = model;
    API_SERVER_PORT = "8642";
    HERMES_CA_BUNDLE = "/managed-ca";
    SEARXNG_URL = "https://searxng.vulcan.lan";
    SSL_CERT_FILE = "/managed-ca";
  };
assert
  service.extraPlugins == [
    pkgs.hermes-local-extract
    pkgs.hermes-qdrant-memory
  ];
runCommand "hermes-renderer-contract"
  {
    integrationPackages = [
      pkgs.hermes-local-extract
      pkgs.hermes-org-db-mcp
      pkgs.hermes-qdrant-memory
    ];
  }
  ''
    for package in $integrationPackages; do
      test -e "$package"
    done
    touch "$out"
  ''
