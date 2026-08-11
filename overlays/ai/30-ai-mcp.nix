# MCP package exposure.
{
  palMcpServer ? null,
}:
final: prev:

import ../../packages/ai-mcp.nix {
  inherit
    final
    palMcpServer
    prev
    ;
}
