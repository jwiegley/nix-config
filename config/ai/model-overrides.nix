let
  llamaSwapOverrides = {
    modelOverrides."GLM-5.2".contextWindow = 262144;
  };
  omlxOverrides = {
    modelOverrides."DeepSeek-V4-Flash-0731-MXFP4-MLX".contextWindow = 262144;
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
      omlx-clio = { };
      omlx-hera = {
        inherit (omlxOverrides) modelOverrides;
      };
    };
  };
}
