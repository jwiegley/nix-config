let
  models = import ./models.nix;
  deepseekThinkingLevelMap = {
    minimal = null;
    low = null;
    medium = null;
    high = null;
    xhigh = null;
    max = "max";
  };
  llamaSwapOverrides = {
    modelOverrides.${models.llamaSwap.name}.contextWindow = models.llamaSwap.contextWindow;
  };
  qwenOverrides = {
    modelOverrides.${models.omlx.primary.name} = {
      contextWindow = models.omlx.primary.contextWindow;
      maxTokens = models.omlx.primary.maxTokens;
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
    modelOverrides.${models.omlx.reasoning.name} = {
      contextWindow = models.omlx.reasoning.contextWindow;
      maxTokens = models.omlx.reasoning.maxTokens;
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
  nativeProviders = {
    openai-codex.modelOverrides.${models.codex.name}.contextWindow = models.codex.contextWindow;
    openrouter.modelOverrides.${models.openrouter.name}.contextWindow = models.openrouter.contextWindow;
  };

  # Generic local provider names are consumed by clients whose configuration
  # addresses only the machine-local service.
  localProviderOverrides = {
    llama-swap = llamaSwapOverrides;
    omlx = omlxOverrides;
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
