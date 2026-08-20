{ lib, pkgs }:

{
  projection,
  homeDirectory,
  xdgConfigHome,
}:

let
  json = pkgs.formats.json { };
  renderLib = import ./render-lib.nix { inherit lib; };
  inherit (renderLib) isTypedEnv;
  renderManagedStdio = (import ../managed-stdio.nix { inherit lib; }).render pkgs;

  hasOnlyKeys =
    allowed: value: builtins.all (name: builtins.elem name allowed) (builtins.attrNames value);
  isSafeUrl =
    value:
    builtins.isString value
    && builtins.all (fragment: !(lib.hasInfix fragment value)) [
      "$"
      "{env:"
      "$env:"
      "?apiKey="
    ];
  renderEnvValue =
    value:
    if builtins.isString value then value else throw "unsupported MCP registry environment value";
  renderServer =
    _: server:
    let
      transport = renderManagedStdio server.transport;
      environment = lib.filterAttrs (_: value: !isTypedEnv value) (transport.env or { });
    in
    if transport ? url then
      assert hasOnlyKeys [ "url" ] transport;
      assert isSafeUrl transport.url;
      {
        inherit (transport) url;
        oauth = false;
      }
    else
      assert hasOnlyKeys [
        "args"
        "command"
        "env"
      ] transport;
      assert builtins.isString transport.command;
      assert builtins.isList transport.args && builtins.all builtins.isString transport.args;
      {
        inherit (transport) command args;
      }
      // lib.optionalAttrs (environment != { }) {
        env = lib.mapAttrs (_: renderEnvValue) environment;
      };

  xdgConfigRelative = lib.removePrefix "${homeDirectory}/" xdgConfigHome;
  globalMcpPath = "${xdgConfigRelative}/mcp/mcp.json";
in
assert builtins.isString homeDirectory;
assert xdgConfigHome == "${homeDirectory}/.config";
assert projection.mutableMcpPaths != [ ];
{
  files."${globalMcpPath}".source = json.generate "nix-managed-mcp.json" {
    mcpServers = lib.mapAttrs renderServer projection.mcpServers;
    settings.mcpFooterStatus = "compact";
  };

  mutableMcpGuards = map (path: {
    inherit path;
    forbiddenKeys = [
      "mcpServers"
      "imports"
    ];
  }) projection.mutableMcpPaths;
}
