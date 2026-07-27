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
      "claude-vault"
      "context-hub"
      "context7-mcp"
      "gguf-tools"
      "github-mcp-server"
      "guidellm"
      "lazycodex-ai"
      "llama-swap"
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
      "plasma-fractal"
      "plasma-wiki"
    ];

    featureOwned = [
      "agent-deck"
      "plasma-fractal"
      "plasma-wiki"
    ];
  };
}
