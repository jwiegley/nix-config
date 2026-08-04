# MCP package exposure.
{
  palMcpServer ? null,
  mcpRemote ? null,
}:
final: prev:

import ../../packages/ai-mcp.nix {
  inherit
    final
    mcpRemote
    palMcpServer
    prev
    ;
}
