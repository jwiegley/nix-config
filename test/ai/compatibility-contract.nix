# Package, input, and app expectations below are literals. A contract that
# derives those names from the implementation moves "expected" and "actual"
# together, so deleting an input or gallery member could never fail it. Systems
# and checks belong to the separately validated closeout manifest.
let
  checkManifest = import ../check-manifest.nix;
in
{
  inherit (checkManifest) systems;

  inputs = [
    "agent-browser-source"
    "git-ai"
    "llm-agents"
    "mcp-servers-nix"
    "npm-cache-nixpkgs"
    "nixpkgs"
    "pal-mcp-server"
    "pi-btw"
    "pi-mcp-adapter"
    "pi-openai-server-compaction"
    "pi-quiet"
    "ponytail"
    "rust-overlay"
    "translate-tool"
  ];

  packages = builtins.sort builtins.lessThan [
    "agent-browser"
    "agent-resources"
    "cymbal"
    "codex"
    "default"
    "droid"
    "nix-scripts"
    "pi"
    "pi-agent-browser-native"
    "pi-blackhole"
    "pi-btw"
    "pi-cache-optimizer"
    "pi-caveman"
    "pi-copy-message"
    "pi-cymbal"
    "pi-droid-sdk"
    "pi-dynamic-workflows"
    "pi-gallery"
    "pi-goal-x"
    "pi-hashline-edit-pro"
    "pi-bifrost"
    "pi-lens"
    "pi-loop"
    "pi-markdown-preview"
    "pi-mem"
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

}
