let
  llamaSwapOverrides = {
    modelOverrides."GLM-5.2".contextWindow = 262144;
  };
  omlxOverrides = {
    modelOverrides."DeepSeek-V4-Flash-0731-oQ8e-mtp".contextWindow = 262144;
  };
  piRouterTarget = {
    id = "Qwen3.6-27B-oQ6e-mtp";
    contextLimit = 262144;
    outputLimit = 65536;
    defaultThinkingLevel = "off";
    reasoning = true;
    input = [ "text" ];
    thinkingLevels = [
      "off"
      "high"
    ];
    thinkingLevelMap = {
      minimal = null;
      low = null;
      medium = null;
      high = "high";
      xhigh = null;
      max = null;
    };
    compat = {
      supportsReasoningEffort = false;
      thinkingFormat = "qwen-chat-template";
    };
  };
in
{
  nativeProviders = {
    openai-codex.modelOverrides."gpt-5.6-sol".contextWindow = 1050000;
    openrouter.modelOverrides."z-ai/glm-5.2".contextWindow = 1048576;
  };

  # Generic local provider names are consumed by clients whose configuration
  # addresses only the machine-local service.
  localProviderOverrides = {
    llama-swap = llamaSwapOverrides;
    omlx = omlxOverrides;
  };

  # Pi discovery names are globally stable provider identities. Keep their
  # final names and model policy in data so the renderer projects whatever
  # complete provider set the catalog validates.
  pi = {
    localProviderOverrides = {
      llama-swap = llamaSwapOverrides;
      omlx-clio = { };
      omlx-hera = {
        modelOverrides = omlxOverrides.modelOverrides // {
          "${piRouterTarget.id}" = {
            contextWindow = piRouterTarget.contextLimit;
            maxTokens = piRouterTarget.outputLimit;
            inherit (piRouterTarget)
              compat
              defaultThinkingLevel
              input
              reasoning
              thinkingLevelMap
              ;
          };
        };
      };
    };
    router = {
      provider = "omlx-hera";
      target = piRouterTarget;
    };
  };
}
