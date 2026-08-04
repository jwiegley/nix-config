{
  allowedHosts = [
    "clio"
    "hera"
  ];

  allowedNonSecretCredentialsByProvider = {
    llama-swap = "not-needed";
    omlx = "dummy-key";
    omlx-remote = "dummy-key";
  };

  allowedInsecureBaseUrlsByProvider = {
    llama-swap = "http://localhost:8080/v1";
    omlx = "http://localhost:8000/v1";
  };

  syncChatPath = "chat/completions";

  providers = {
    omlx-remote = {
      selectors.clients = [
        "droid"
      ];
      droid = {
        providerType = "generic-chat-completion-api";
        noImageSupport = true;
      };
    };

    omlx = {
      selectors.clients = [
        "droid"
        "pi"
      ];
      droid = {
        providerType = "generic-chat-completion-api";
        noImageSupport = true;
      };
    };

    llama-swap = {
      selectors.clients = [
        "droid"
        "pi"
      ];
      droid = {
        providerType = "generic-chat-completion-api";
        noImageSupport = true;
      };
    };
  };
}
