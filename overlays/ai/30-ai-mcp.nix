# MCP package exposure and compatibility overrides.
{
  palMcpServer ? null,
  mcpRemote ? null,
}:
final: prev:

(import ../../packages/ai-mcp.nix {
  inherit
    final
    mcpRemote
    palMcpServer
    prev
    ;
})
// {
  # npm prune removes @types/node, then the prepare script tries to rebuild.
  mcp-server-sequential-thinking = prev.mcp-server-sequential-thinking.overrideAttrs (_old: {
    dontNpmPrune = true;
  });
}
