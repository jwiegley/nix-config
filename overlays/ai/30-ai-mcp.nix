# MCP package exposure.
{
  llmAgents ? null,
  palMcpServer ? null,
}:
final: prev:

import ../../packages/ai-mcp.nix {
  inherit
    final
    llmAgents
    palMcpServer
    prev
    ;
}
