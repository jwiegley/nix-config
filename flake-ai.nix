# Shared AI/agent overlay + packages, host-agnostic.
# Consumed by this repo's flake.nix AND by downstream hosts that import this
# repo as a `flake = false` source, e.g.:
#   import "${inputs.nix-config}/flake-ai.nix" inputs
# Requires ONLY the AI/agent inputs (NOT this repo's Darwin git+file inputs):
#   nixpkgs llm-agents git-ai rust-overlay mcp-servers-nix mcp-remote
#   pal-mcp-server agent-browser-source bigpowers lean-ctx pi-btw
#   pi-subagentura ponytail translate-tool pi-mcp-adapter
#   pi-openai-server-compaction pi-quiet
inputs: import ./packages/ai-flake-outputs.nix inputs
