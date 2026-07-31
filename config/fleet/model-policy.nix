{
  allowedHosts = [
    "clio"
    "hera"
  ];

  allowedNonSecretCredentialsByProvider = {
    llama-cpp-local = "not-needed";
    omlx = "dummy-key";
    omlx-remote = "dummy-key";
  };

  allowedInsecureBaseUrlsByProvider = {
    llama-cpp-local = "http://localhost:8080/v1";
    omlx = "http://localhost:8000/v1";
  };

  profileDefaultProfiles = [ ];

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

    omlx-remote = {
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
        name = "oMLX (Remote)";
        timeout = false;
      };
    };

    omlx = {
      selectors.clients = [
        "droid"
        "opencode"
        "pi"
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
        "pi"
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
