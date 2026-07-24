{
  systems = [
    "aarch64-darwin"
    "aarch64-linux"
    "x86_64-linux"
  ];

  inputs = [
    "git-ai"
    "llm-agents"
    "mcp-remote"
    "mcp-servers-nix"
    "nixpkgs"
    "pal-mcp-server"
    "pi-mcp-adapter"
    "pi-openai-server-compaction"
    "pi-quiet"
    "pi-subagent"
    "ponytail"
    "rust-overlay"
    "superpowers"
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
    "agent-http-header-bridge"
    "agent-resources"
    "default"
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
    "profile"
    "tests"
  ];
}
