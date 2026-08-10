# Every expectation below is a LITERAL. A contract that derives its required
# names from the lock or the gallery manifest moves "expected" and "actual"
# together, so deleting an input or a gallery member could never fail it;
# with literals, every removal is a visible, deliberate edit to this file.
{
  systems = [
    "aarch64-darwin"
    "aarch64-linux"
    "x86_64-linux"
  ];

  inputs = [
    "agent-browser-source"
    "git-ai"
    "llm-agents"
    "mcp-remote"
    "mcp-servers-nix"
    "nixpkgs"
    "obr"
    "pal-mcp-server"
    "pi-btw"
    "pi-llm-agents"
    "pi-mcp-adapter"
    "pi-openai-server-compaction"
    "pi-quiet"
    "ponytail"
    "rust-overlay"
    "translate-tool"
  ];

  packages = builtins.sort builtins.lessThan [
    "agent-browser"
    "agent-http-header-bridge"
    "agent-resources"
    "cymbal"
    "default"
    "nix-scripts"
    "obr"
    "pi"
    "pi-agent-browser-native"
    "pi-artifacts"
    "pi-blackhole"
    "pi-btw"
    "pi-cache-optimizer"
    "pi-caveman"
    "pi-copy-message"
    "pi-cymbal"
    "pi-dynamic-workflows"
    "pi-gallery"
    "pi-goal-x"
    "pi-hashline-edit-pro"
    "pi-insights"
    "pi-lens"
    "pi-loop"
    "pi-markdown-preview"
    "pi-model-router"
    "pi-multi-pass"
    "pi-ponytail"
    "pi-provider-llama-swap"
    "pi-provider-omlx"
    "pi-rewind"
    "pi-rtk-optimizer"
    "pi-smart-fetch"
    "pi-smart-web-search"
    "pi-subagents"
    "pi-trace-extension"
    "pi-usage-extension"
    "plasma-fractal"
    "plasma-wiki"
    "prime-agent"
    "rtk"
  ];

  # Truthful evidence-bearing app names plus the conventional `default` alias.
  # `no-warnings` is a real app running no-warnings.sh.
  apps = [
    "build-check"
    "check"
    "default"
    "format"
    "format-check"
    "lint"
    "no-warnings"
    "test"
  ];

  # `compatibility-contract` is grafted onto the checked output after this list
  # is compared with the portable definition, so it is deliberately absent.
  # Retired check aliases produced no independent evidence; the real apps and
  # behavioral checks remain.
  checks = [
    "agent-deck-go-compat"
    "agent-deck-runtime-lifecycle"
    "agent-resources"
    "agent-wrappers"
    "build"
    "format"
    "fractal-smoke"
    "lint"
    "llama-cpp-platform-compat"
    "llm-agents-nixpkgs-independent"
    "pi-extension-tests"
    "pi-fleet-theme"
    "pi-gallery"
    "pi-session-replacement"
    "prime-agent"
  ];
}
