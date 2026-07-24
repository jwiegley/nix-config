{
  systems = [
    "aarch64-darwin"
    "aarch64-linux"
    "x86_64-linux"
  ];

  inputs = [
    "agent-browser-source"
    "bigpowers"
    "git-ai"
    "lean-ctx"
    "llm-agents"
    "mcp-remote"
    "mcp-servers-nix"
    "nixpkgs"
    "pal-mcp-server"
    "pi-agent-browser-native"
    "pi-artifacts"
    "pi-btw"
    "pi-dynamic-workflows"
    "pi-hashline-edit-pro"
    "pi-insights"
    "pi-lens"
    "pi-mcp-adapter"
    "pi-openai-server-compaction"
    "pi-quiet"
    "pi-subagentura"
    "pi-web-access"
    "ponytail"
    "rust-overlay"
    "translate-tool"
  ];

  topLevel = [
    [
      "overlays"
      "default"
    ]
    [
      "lib"
      "aiPackagesFor"
    ]
    [
      "lib"
      "patchAgentPackage"
    ]
  ];

  packages = [
    "agent-browser"
    "agent-http-header-bridge"
    "agent-resources"
    "bigpowers"
    "default"
    "lean-ctx"
    "pi-agent-browser-native"
    "pi-artifacts"
    "pi-btw"
    "pi-dynamic-workflows"
    "pi-gallery"
    "pi-hashline-edit-pro"
    "pi-insights"
    "pi-lean-ctx"
    "pi-lens"
    "pi-model-router"
    "pi-ponytail"
    "pi-provider-litellm"
    "pi-rewind"
    "pi-scroll"
    "pi-subagentura"
    "pi-web-access"
    "plasma-fractal"
    "plasma-wiki"
  ];

  apps = [
    "build-check"
    "check"
    "coverage"
    "coverage-check"
    "default"
    "format"
    "format-check"
    "fuzz"
    "lint"
    "memory-check"
    "no-warnings"
    "profile"
    "profile-check"
    "test"
  ];

  checks = [
    "agent-deck-go-compat"
    "agent-resources"
    "agent-wrappers"
    "build"
    "coverage"
    "format"
    "fractal-smoke"
    "fuzz"
    "lint"
    "llama-cpp-platform-compat"
    "llm-agents-nixpkgs-independent"
    "memory"
    "no-warnings"
    "pi-gallery"
    "profile"
    "tests"
  ];
}
