let
  models = import ./models.nix;
  llamaSwapOverrides = {
    modelOverrides.${models.llamaSwap.name}.contextWindow = models.llamaSwap.contextWindow;
  };
  omlxOverrides = {
    modelOverrides.${models.omlx.reasoning.name}.contextWindow = models.omlx.reasoning.contextWindow;
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
      omlx-clio = { };
      omlx-hera = {
        inherit (omlxOverrides) modelOverrides;
      };
    };
  };
}
