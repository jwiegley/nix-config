# Single source of truth for managed model selection and provider overrides.
# Move replaced oMLX names to retiredModels so mutable Pi settings migrate away
# from them without repeating model history in consumers or tests.
let
  openai = {
    astra = "gpt-6-astra";
    sol = "gpt-5.6-sol";
    terra = "gpt-5.6-terra";
    luna = "gpt-5.6-luna";
  };
  anthropic = {
    opus = "claude-opus-5";
    sonnet = "claude-sonnet-5";
    haiku = "claude-haiku-4-5-20251001";
    fable = "claude-fable-5";
    sonnetLegacy = "claude-sonnet-4-20250514";
    opusLegacy = "claude-opus-4-20250514";
    sonnet45 = "claude-sonnet-4-5-20250929";
  };
  geminiPro = "gemini-3.1-pro-preview";
  deepseekFlash = "DeepSeek-V4-Flash-0731-MXFP4-MLX";
  claude = {
    name = "${anthropic.opus}[1m]";
    haiku = anthropic.sonnet;
    subagent = anthropic.opus;
    maxOutputTokens = 64000;
    effort = "max";
  };
  perplexity = {
    sonar = "sonar-pro";
    reasoning = "sonar-reasoning-pro";
    research = "sonar-deep-research";
  };
  scriptPi = {
    provider = "openai-codex";
    model = codex.name;
  };
  hermes.name = "hermes-agent";
  codex = {
    name = openai.astra;
    reasoningEffort = "ultra";
    autoCompactPercent = 80;
    modelOverrides = {
      ${openai.sol}.contextWindow = 1050000;
      ${openai.astra}.contextWindow = 1050000;
    };
  };
  openrouter = {
    name = "z-ai/glm-5.2";
    contextWindow = 1048576;
  };
  llamaSwap = {
    name = "GLM-5.2";
    contextWindow = 262144;
  };
  embeddings = rec {
    gguf = "bge-m3";
    omlx = "bge-m3-mlx-fp16";
    host = "hera";
    local = "${host}/${omlx}";
    remote = "openai/text-embedding-3-large";
    localDefinition = {
      backend = "openai-compatible";
      kind = "text";
      reference = local;
      provider = host;
      model = omlx;
      dimension = 1024;
      metric = "cosine";
      requestTimeoutMs = 600000;
      maxBatchSize = 20;
      maxInputTokens = 8192;
    };
  };
  nixosRetryPolicy = {
    maxSeconds = 3600;
    initialDelay = 5;
    maxDelay = 60;
  };
  omlxHosts = [
    "clio"
    "hera"
  ];
  omlxProviders = map (host: "omlx-${host}") omlxHosts;
  omlxRoles = {
    primary = {
      name = "Qwen3.8-27B-oQ4e-mtp";
      providers = omlxProviders;
      retiredNames = [ "Qwen3.8-27B-oQ6e-mtp-mlx" ];
      contextWindow = 262144;
      maxTokens = 81920;
    };
    reasoning = {
      name = "GLM-5.3-Flash-oQ4e";
      providers = [ "omlx-hera" ];
      retiredNames = [ ];
      contextWindow = 262144;
      maxTokens = 81920;
    };
  };
  omlxRoleValues = builtins.attrValues omlxRoles;
  retiredOmlxModels = builtins.concatLists (map (role: role.retiredNames) omlxRoleValues);
  omlxReplacementPairs = builtins.concatLists (
    map (
      role:
      builtins.concatLists (
        map (
          provider:
          map (retired: {
            name = "${provider}/${retired}";
            value = "${provider}/${role.name}";
          }) role.retiredNames
        ) role.providers
      )
    ) omlxRoleValues
  );
  staleOmlxPatterns = builtins.concatLists (
    map (
      provider:
      map (name: "${provider}/${name}") retiredOmlxModels
      ++ builtins.concatLists (
        map (role: if builtins.elem provider role.providers then [ ] else [ "${provider}/${role.name}" ]) (
          builtins.attrValues omlxRoles
        )
      )
    ) omlxProviders
  );
  deepseekThinkingLevelMap = {
    minimal = null;
    low = null;
    medium = null;
    high = null;
    xhigh = null;
    max = "max";
  };
  llamaSwapOverrides = {
    modelOverrides.${llamaSwap.name}.contextWindow = llamaSwap.contextWindow;
  };
  qwenOverrides = {
    modelOverrides.${omlxRoles.primary.name} = {
      contextWindow = omlxRoles.primary.contextWindow;
      maxTokens = omlxRoles.primary.maxTokens;
      reasoning = false;
      input = [ "text" ];
      compat = {
        supportsDeveloperRole = false;
        supportsReasoningEffort = false;
        thinkingFormat = "qwen-chat-template";
      };
    };
  };
  omlxOverrides = {
    modelOverrides.${omlxRoles.reasoning.name} = {
      contextWindow = omlxRoles.reasoning.contextWindow;
      maxTokens = omlxRoles.reasoning.maxTokens;
      reasoning = true;
      input = [ "text" ];
      thinkingLevelMap = deepseekThinkingLevelMap;
      compat = {
        supportsDeveloperRole = false;
        supportsReasoningEffort = true;
        requiresReasoningContentOnAssistantMessages = true;
        thinkingFormat = "deepseek";
      };
    };
  };
in
{
  inherit
    anthropic
    claude
    codex
    embeddings
    hermes
    openai
    openrouter
    perplexity
    llamaSwap
    ;
  scripts = {
    ai = {
      claude = anthropic.fable;
      codex = codex.name;
      omlx = omlxRoles.reasoning.name;
      inherit (claude) effort;
      anthropicFallback = "sonnet";
    };
    startAgent = {
      codex = codex.name;
      claude = claude.name;
      claudeEffort = claude.effort;
      pi = scriptPi;
    };
    ppi = scriptPi;
    claudeAlias = "opus";
    ask = {
      temperature = 0.7;
      openai = "gpt-4.1";
      anthropic = anthropic.sonnetLegacy;
      openrouter = "deepseek/deepseek-r1-0528:free";
      perplexity = perplexity.sonar;
    };
    geminiToOrg = {
      pi = scriptPi;
      inferenceModel = omlxRoles.reasoning.name;
      claudeModel = anthropic.sonnet45;
      shorteningTokens = 1000;
      titleTokens = 2000;
      cleanupTokens = 8192;
      inferenceTokens = 12000;
      selectionTokens = 8000;
    };
    mlxBench =
      let
        large = "mlx-community/gpt-oss-120b-MXFP4-Q8";
        small = "mlx-community/gpt-oss-20b-MXFP4-Q8";
      in
      [
        { model = large; }
        {
          model = large;
          draftModel = small;
        }
        { model = "openai/gpt-oss-20b"; }
        { model = small; }
        { model = "lmstudio-community/gpt-oss-safeguard-20b-MLX-MXFP4"; }
      ];
    numberParagraphs = {
      models = {
        sonnet = anthropic.sonnetLegacy;
        opus = anthropic.opusLegacy;
      };
      maxTokens = 2000;
    };
  };
  advisors = {
    pal = {
      reasoning = geminiPro;
      partner = "gpt-5.5-pro";
    };
    validation = [
      anthropic.fable
      openai.sol
    ];
    forge = [
      "fable"
      "opus"
    ];
  };
  agentCat =
    let
      model = engine: name: {
        inherit engine;
        select = [ { exact = name; } ];
      };
      rung = model: thinking: {
        inherit model thinking;
        max-output = "unconstrained";
      };
      profile = chain: { inherit chain; };
      deckSession = "nix";
      nativeEngines = [
        "claude"
        "codex"
        "droid"
      ];
      nativeModels = [
        "claude-fable"
        "claude-opus"
        "codex-sol"
        "codex-terra"
        "codex-luna"
        "droid-deepseek-v4-pro"
        "droid-grok-4.6"
        "droid-glm-5.3"
        "droid-gemini-3.1-pro"
      ];
    in
    {
      default-persona = "personal";
      engines = {
        claude = {
          backend = "acp:claude";
          provider = "anthropic";
        };
        codex = {
          backend = "acp:codex";
          provider = "openai-codex";
        };
        droid = {
          backend = "acp:droid";
          provider = "factory";
        };
        deck-nix = {
          backend = "deck:${deckSession}";
          provider = "agent-deck";
        };
      };
      models = {
        claude-fable = model "claude" "claude-fable-5-1[1m]";
        claude-opus = model "claude" "opus[1m]";
        codex-sol = model "codex" openai.sol;
        codex-terra = model "codex" openai.terra;
        codex-luna = model "codex" openai.luna;
        droid-deepseek-v4-pro = model "droid" "deepseek-v4-pro";
        "droid-grok-4.6" = model "droid" "grok-4.6";
        "droid-glm-5.3" = model "droid" "glm-5.3";
        "droid-gemini-3.1-pro" = model "droid" geminiPro;
        deck-nix = model "deck-nix" deckSession;
      };
      personas = {
        personal = {
          engines = nativeEngines ++ [ "deck-nix" ];
          models = nativeModels ++ [ "deck-nix" ];
          profiles = {
            deep = profile [
              (rung "claude-opus" "max")
              (rung "droid-deepseek-v4-pro" "max")
              (rung "codex-sol" "max")
            ];
            balanced = profile [
              (rung "codex-terra" "high")
              (rung "claude-fable" "high")
            ];
            review = profile [
              (rung "droid-grok-4.6" "high")
              (rung "claude-opus" "high")
            ];
            reasoning = profile [
              (rung "droid-deepseek-v4-pro" "max")
              (rung "claude-opus" "max")
            ];
            coding = profile [
              (rung "codex-sol" "max")
              (rung "claude-fable" "high")
            ];
            fable = profile [
              (rung "claude-fable" "high")
              (rung "codex-terra" "high")
            ];
            nix = profile [ (rung "deck-nix" "medium") ];
            "gpt-5.5-xhigh" = profile [ (rung "codex-sol" "xhigh") ];
            opencode = profile [ (rung "droid-deepseek-v4-pro" "high") ];
            opus = profile [ (rung "claude-opus" "max") ];
            deep-thinker = profile [
              (rung "droid-deepseek-v4-pro" "max")
              (rung "claude-opus" "max")
            ];
            "gemini-3.1-pro-preview" = profile [
              (rung "droid-gemini-3.1-pro" "max")
              (rung "droid-grok-4.6" "high")
            ];
            "gpt-5.5-pro" = profile [
              (rung "codex-sol" "high")
              (rung "claude-fable" "high")
            ];
            worker = profile [
              (rung "droid-deepseek-v4-pro" "high")
              (rung "codex-sol" "high")
            ];
            partner = profile [
              (rung "droid-grok-4.6" "max")
              (rung "claude-opus" "high")
            ];
          };
        };
        emacs = {
          engines = nativeEngines;
          models = nativeModels;
          profiles = {
            title = profile [ (rung "codex-terra" "medium") ];
            rewrite = profile [ (rung "claude-fable" "high") ];
            gpt = profile [ (rung "codex-terra" "high") ];
          };
        };
      };
    };
  emacs = rec {
    defaultInstance = deepseekFlash;
    temperature = 1.0;
    thinkingBudget = 32000;
    highOutputTokens = 32000;
    quickModels = {
      claude = "claude-3-7-sonnet-20250219";
      gemini = "gemini-2.0-flash";
      gpt = "gpt-4o-mini";
    };
    parents = {
      qwen-clio = [ "qwen" ];
      default = [ "rewrite" ];
      analyze = [
        "opus-max"
        "high-output"
      ];
      code = [ "analyze" ];
      search = [
        "analyze"
        "web-search"
      ];
      rewrite = [ "gpt" ];
      prompt = [ "opus" ];
      title = [ "rewrite" ];
      infer-tasks = [ "rewrite" ];
      persian = [ "sonnet" ];
      spanish = [ "sonnet" ];
      cli = [ "sonnet" ];
      emacs = [ "sonnet" ];
      haskell = [ "sonnet" ];
      web = [ "sonar" ];
      deep = [ "sonar" ];
      research = [ "sonar-deep-research" ];
      shorten = [ "rewrite" ];
      breakdown = [ "rewrite" ];
      proof = [ "rewrite" ];
      docstring = [
        "emacs"
        "rewrite"
      ];
      commit-summary = [ "rewrite" ];
    };
    presets = {
      gpt = openai.terra;
      opus = "claude-opus-4-8";
      inherit (anthropic) sonnet haiku;
      opus-max = "${presets.opus}-thinking-${toString thinkingBudget}";
      sonnet-max = "${presets.sonnet}-thinking-${toString thinkingBudget}";
      inherit (perplexity) sonar;
      sonar-pro = perplexity.reasoning;
      sonar-deep-research = perplexity.research;
    };
    providerModels = {
      perplexity = [
        presets.sonar
        presets.sonar-pro
        presets.sonar-deep-research
      ];
      vibe-proxy =
        let
          opus = "claude-opus-4-7";
          sonnet = "claude-sonnet-4-6";
        in
        [
          "factory/deepseek-v4-pro"
          opus
          "${opus}-thinking-${toString thinkingBudget}"
          sonnet
          "${sonnet}-thinking-${toString thinkingBudget}"
        ];
      rinzler = [ "llama31-metal" ];
      rinzler-andoria = [ "zai-org/GLM-4.7-Flash" ];
      hermes = [ hermes.name ];
    };
    llamaSwap = {
      alwaysOn = [ embeddings.gguf ];
      preload = [ embeddings.gguf ];
    };
    inferenceDefaults = {
      contextWindow = 262144;
      maxTokens = 81920;
      temperature = 1.0;
      minP = 0.01;
      topP = 0.9;
      topK = 20;
    };
    models =
      let
        anthropicInstances =
          name:
          map (provider: { inherit name provider; }) [
            "vibe-proxy"
            "anthropic"
          ];
        thinkingInstance = name: {
          name = "${name}-thinking-${toString thinkingBudget}";
          provider = "vibe-proxy";
        };
        defaults = {
          context-length = inferenceDefaults.contextWindow;
          max-output-tokens = inferenceDefaults.maxTokens;
          inherit (inferenceDefaults) temperature;
          min-p = inferenceDefaults.minP;
          top-p = inferenceDefaults.topP;
          top-k = inferenceDefaults.topK;
        };
      in
      map (model: defaults // model) [
        {
          name = embeddings.gguf;
          context-length = 8192;
          kind = "embedding";
          instances = [
            {
              model-path = "~/Models/gpustack_bge-m3-GGUF";
              # Retain the tested llama.cpp concurrency cap.
              parallel = 16;
              concurrency-limit = 32;
              hostnames = [
                "hera"
                "clio"
              ];
              arguments = [
                "--embedding"
                "--pooling"
                "mean"
                "--batch-size"
                "8192"
                "--ubatch-size"
                "4096"
              ];
            }
            {
              name = embeddings.omlx;
              provider = "omlx";
            }
          ];
        }
        {
          name = "bge-reranker-v2-m3";
          kind = "reranker";
          instances = [
            {
              model-path = "~/Models/gpustack_bge-reranker-v2-m3-GGUF";
              hostnames = [
                "hera"
                "clio"
              ];
              arguments = [
                "--reranking"
                "--batch-size"
                "8192"
                "--ubatch-size"
                "4096"
              ];
            }
          ];
        }
        {
          name = "claude-fable";
          instances = [ (thinkingInstance anthropic.fable) ] ++ anthropicInstances anthropic.fable;
        }
        {
          name = "claude-haiku";
          instances = anthropicInstances anthropic.haiku;
        }
        {
          name = "claude-opus";
          instances = [ (thinkingInstance anthropic.opus) ] ++ anthropicInstances anthropic.opus;
        }
        {
          name = "claude-sonnet";
          instances = [ (thinkingInstance anthropic.sonnet) ] ++ anthropicInstances anthropic.sonnet;
        }
        {
          name = "cohere-transcribe-03-2026";
          kind = "audio-transcription";
          instances = [
            {
              name = "cohere-transcribe-03-2026-mlx-fp16";
              provider = "omlx";
            }
            { model-path = "~/Models/cstr_cohere-transcribe-03-2026-GGUF"; }
          ];
        }
        {
          name = "DeepSeek-V4-Flash-0731";
          context-length = 262144;
          instances = [
            {
              name = deepseekFlash;
              provider = "omlx";
            }
            {
              name = "deepseek/deepseek-v4-flash-0731";
              context-length = 1048576;
              provider = "openrouter";
            }
          ];
        }
        {
          name = "GLM-5.2";
          instances = [
            {
              inherit (openrouter) name;
              context-length = openrouter.contextWindow;
              provider = "openrouter";
            }
          ];
        }
        {
          name = "granite-speech-4.1-2b";
          kind = "audio-transcription";
          instances = [ { model-path = "~/Models/cstr_granite-speech-4.1-2b-GGUF"; } ];
        }
        {
          name = "Kimi-K3";
          context-length = 1048576;
          instances = [
            {
              name = "moonshotai/kimi-k3";
              provider = "openrouter";
            }
          ];
        }
        {
          name = "Meta-Llama-3.1-8B";
          instances = [ { model-path = "~/Models/mradermacher_Meta-Llama-3.1-8B-GGUF"; } ];
        }
        {
          name = "nomic-embed-text-v2-moe";
          context-length = 512;
          kind = "embedding";
          instances = [
            {
              model-path = "~/Models/nomic-ai_nomic-embed-text-v2-moe-GGUF";
              arguments = [
                "--embedding"
                "--pooling"
                "mean"
                "--batch-size"
                "8192"
                "--ubatch-size"
                "4096"
              ];
            }
          ];
        }
        {
          name = "Qwen3.8-27B";
          context-length = 262144;
          instances = [
            {
              name = omlxRoles.primary.name;
              hostnames = omlxHosts;
              provider = "omlx";
            }
          ];
        }
        {
          name = "Qwen3.8-Max";
          context-length = 1048576;
          instances = [
            {
              name = "qwen/qwen3.8-max";
              provider = "openrouter";
            }
          ];
        }
      ];
    modelOverrides = {
      ${defaultInstance} = inferenceDefaults;
      ${omlxRoles.primary.name} = inferenceDefaults // {
        inherit (omlxRoles.primary) contextWindow maxTokens;
      };
      ${omlxRoles.reasoning.name} = inferenceDefaults // {
        inherit (omlxRoles.reasoning) contextWindow maxTokens;
      };
    };
  };
  recordings = {
    llm = {
      provider = "omlx";
      model = omlxRoles.primary.name;
    };
    asr = {
      model = "cohere-asr";
      language = "en";
    };
  };
  nixos = {
    llm = {
      primary = nixosRetryPolicy // {
        name = omlxRoles.primary.name;
        # Backup models for THIS role, tried in order by the NixOS log
        # summariser, which walks `[primary] + primary.fallbacks`.
        #
        # SCOPED BY NESTING, deliberately. This lived at llm.fallbacks for one
        # commit, where it read as a fallback list for every model in the file
        # rather than for one role. Nesting makes that misreading
        # unrepresentable.
        #
        # It then briefly hung off `reasoning`, which was correct while the
        # summariser used GLM. Operator policy on 2026-09-09 moved log analysis
        # and spam detection to the non-thinking model and reserved GLM for the
        # Hermes agent, so the backup follows the JOB rather than the model it
        # used to run on -- left under `reasoning` it would be dead config that
        # nothing reads.
        #
        # NOTE its value is narrower here than behind GLM: `:thinking` is the
        # same base model with reasoning enabled on the same backend, so a
        # failure taking out the primary will often take this with it. A second
        # chance, not an independent one. Drop it if that is not worth the config.
        #
        # Safe to attach here: models.llm.primary is consumed only via `.name`
        # (stock-trader, open-webui), never wholesale in restartTriggers, so
        # adding a key restarts nothing -- unlike llm.reasoning, which feeds
        # hermes-microvm.nix restartTriggers.
        #
        # maxSeconds 900 rather than the 3600 default: the summariser caps its
        # whole AI stage at 1800s, itself under logwatch.service's 45min.
        fallbacks = [
          (
            nixosRetryPolicy
            // {
              name = "${omlxRoles.primary.name}:thinking";
              maxSeconds = 900;
            }
          )
        ];
      };
      fast = nixosRetryPolicy // {
        name = omlxRoles.primary.name;
        maxSeconds = 120;
      };
      reasoning = nixosRetryPolicy // {
        name = omlxRoles.reasoning.name;
        inherit (omlxOverrides.modelOverrides.${omlxRoles.reasoning.name}) maxTokens reasoning input;
        # Preserve the existing NixOS reasoning callers' context budget.
        contextWindow = 1048576;
        api = "openai-completions";
        cost = {
          input = 0;
          output = 0;
          cacheRead = 0;
          cacheWrite = 0;
        };
      };
    };
    embedding = {
      primary.name = embeddings.omlx;
      fallbacks = [ ];
    };
  };
  agentAliases = {
    default = "gpt sol";
    aliases = {
      deepseek = {
        harness = "pi";
        provider = "omlx-hera";
        model = omlxRoles.reasoning.name;
        thinking = "max";
      };
      "gpt sol" = {
        harness = "pi";
        provider = "openai-codex";
        model = codex.name;
        thinking = "max";
      };
    };
  };
  prime.thinkingLevel = "xhigh";
  omlx = omlxRoles // {
    providers = omlxProviders;
    retiredModels = retiredOmlxModels;
    replacements = builtins.listToAttrs omlxReplacementPairs;
    stalePatterns = staleOmlxPatterns;
  };

  nativeProviders = {
    openai-codex.modelOverrides = codex.modelOverrides;
    openrouter.modelOverrides.${openrouter.name}.contextWindow = openrouter.contextWindow;
  };

  # Generic local provider names are consumed by clients whose configuration
  # addresses only the machine-local service.
  localProviderOverrides = {
    llama-swap = llamaSwapOverrides;
    omlx.modelOverrides = qwenOverrides.modelOverrides // omlxOverrides.modelOverrides;
  };
  # Prime consumes these local identities through the same owner projection as
  # Pi; the adapter never rediscovers ownership or presentation from an ID.
  localGalleryProviders = {
    llama-swap = {
      owner = "llama-swap-provider";
      name = "llama-swap";
    };
    omlx = {
      owner = "omlx-provider";
      name = "oMLX";
      apiKey.env = "OMLX_API_KEY";
    };
  };

  # Pi discovery names are globally stable provider identities. Keep their
  # owner, final names, and model policy in data so the renderer projects
  # whatever complete provider set the catalog validates.
  pi = {
    fastMode = {
      persist = false;
      desired = false;
      tier = "priority";
      models = builtins.concatLists (
        map
          (
            provider:
            map (name: "${provider}/${name}") [
              "gpt-5.4"
              "gpt-5.5"
              "gpt-5.6"
              openai.luna
              openai.terra
              openai.sol
              openai.astra
            ]
          )
          [
            "openai"
            "openai-codex"
          ]
      );
      indicator = "status";
    };
    galleryProviders = {
      llama-swap = {
        owner = "llama-swap-provider";
        name = "llama-swap";
      };
      omlx-clio = {
        owner = "omlx-provider";
        name = "oMLX Clio";
      };
      omlx-hera = {
        owner = "omlx-provider";
        name = "oMLX Hera";
      };
    };
    localProviderOverrides = {
      llama-swap = llamaSwapOverrides;
      omlx-clio = {
        compat.sendSessionAffinityHeaders = true;
      };
      omlx-hera = {
        compat.sendSessionAffinityHeaders = true;
        modelOverrides = qwenOverrides.modelOverrides // omlxOverrides.modelOverrides;
      };
    };
  };
}
