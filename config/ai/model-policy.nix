{
  allowedHosts = [
    "clio"
    "hera"
  ];

  allowedNonSecretCredentialsByProvider = {
    llama-cpp-local = "not-needed";
    llama-cpp-remote = "dummy-api-key";
    omlx = "dummy-key";
  };

  allowedInsecureBaseUrlsByProvider = {
    llama-cpp-local = "http://localhost:8080/v1";
    omlx = "http://hera.lan:8000/v1";
  };

  profileDefaultProfiles = [
    "clio-opencode"
    "hera-opencode"
    "shared-work-opencode-positron"
  ];

  syncChatPath = "chat/completions";

  providers = {
    positron-anthropic = {
      selectors.clients = [ "droid" ];
      droid.providerType = "anthropic";
    };

    positron-google = {
      selectors.clients = [ "droid" ];
      droid = {
        providerType = "generic-chat-completion-api";
        noImageSupport = true;
      };
    };

    positron-openai = {
      selectors.clients = [ "droid" ];
      droid.providerType = "openai";
    };

    nvidia = {
      selectors.clients = [
        "droid"
        "opencode"
      ];
      droid.providerType = "openai";
      opencode = {
        npm = "@ai-sdk/openai-compatible";
        name = "NVIDIA";
        timeout = false;
      };
    };

    litellm = {
      selectors = {
        clients = [
          "droid"
          "opencode"
          "pi"
        ];
        excludeProfiles = [ "vulcan-opencode" ];
      };
      droid = {
        providerType = "generic-chat-completion-api";
        noImageSupport = true;
        extraArgs = {
          min_p = 0;
          temperature = 1;
          top_p = 1;
        };
        extraHeaders.x-litellm-tags = "droid";
      };
      opencode = {
        npm = "@ai-sdk/openai-compatible";
        name = "LiteLLM";
        timeout = false;
      };
    };

    llama-cpp-remote = {
      selectors.clients = [
        "droid"
        "opencode"
      ];
      droid = {
        providerType = "generic-chat-completion-api";
        noImageSupport = true;
      };
      opencode = {
        npm = "@ai-sdk/openai-compatible";
        name = "Llama-Swap (Remote)";
        timeout = false;
      };
    };

    omlx = {
      selectors.clients = [
        "droid"
        "opencode"
      ];
      droid = {
        providerType = "generic-chat-completion-api";
        noImageSupport = true;
      };
      opencode = {
        npm = "@ai-sdk/openai-compatible";
        name = "oMLX";
        timeout = false;
      };
    };

    llama-cpp-local = {
      selectors.clients = [
        "droid"
        "opencode"
      ];
      droid = {
        providerType = "generic-chat-completion-api";
        noImageSupport = true;
      };
      opencode = {
        npm = "@ai-sdk/openai-compatible";
        name = "Llama-Swap";
        timeout = false;
      };
    };
  };
}
