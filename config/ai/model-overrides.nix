{
  nativeProviders = {
    openai-codex.modelOverrides."gpt-5.6-sol".contextWindow = 1050000;
    openrouter.modelOverrides."z-ai/glm-5.2".contextWindow = 1048576;
  };

  localProviderOverrides = {
    llama-swap.modelOverrides."GLM-5.2".contextWindow = 262144;
    omlx.modelOverrides."DeepSeek-V4-Flash-0731-oQ8e-mtp".contextWindow = 262144;
  };
}
