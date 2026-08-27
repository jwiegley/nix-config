{ lib }:

{
  supportsGradio6 =
    pythonPackages: pythonPackages ? gradio && lib.versionAtLeast pythonPackages.gradio.version "6";

  supportsAiperf =
    pythonPackages:
    pythonPackages ? choreographer
    && pythonPackages ? logistro
    && pythonPackages ? gradio
    && lib.versionAtLeast pythonPackages.gradio.version "6";

  groups = {
    common = [
      "agnix"
      "claude-replay"
      "gguf-tools"
      "github-mcp-server"
      "guidellm"
      "lazycodex-ai"
      "llama-swap"
      "mcp-searxng"
      "nix-managed-mcp-stdio"
      "pal-mcp-server"
      "playwright-mcp"
      "qdrant-web-ui"
      "rustdocs-mcp-server"
      "sherlock-db"
    ];

    homeOnly = [ "stock-trader-mcp" ];

    portableOnly = [
      "agent-deck"
      "hfdownloader"
      "openai-whisper"
      "plasma-wiki"
    ];

  };
}
