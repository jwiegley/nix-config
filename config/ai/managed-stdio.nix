{ lib }:

let
  # Keep the subprocess baseline deliberately small. Catalog transports add
  # only their own declared environment names to this list.
  platformEnvironment = [
    "HOME"
    "LANG"
    "LC_ALL"
    "LOGNAME"
    "NIX_SSL_CERT_FILE"
    "NODE_EXTRA_CA_CERTS"
    "SHELL"
    "SSL_CERT_FILE"
    "TERM"
    "TMPDIR"
    "USER"
  ];
  typedEnvironment = [
    "ANTHROPIC_API_KEY"
    "GEMINI_API_KEY"
    "OPENAI_API_KEY"
  ];

  inheritArgument = name: [
    "--inherit"
    name
  ];

  inheritedNamesFor =
    transport:
    lib.sort builtins.lessThan (
      lib.unique (platformEnvironment ++ builtins.attrNames (transport.env or { }))
    );

  normalize =
    transport:
    if transport ? url then
      transport
    else
      transport
      // {
        command = "nix-managed-mcp-stdio";
        args =
          lib.concatMap inheritArgument (inheritedNamesFor transport)
          ++ [
            "--"
            transport.command
          ]
          ++ (transport.args or [ ]);
      };

  packageExecutable =
    pkgs: package: executable:
    assert lib.assertMsg (builtins.hasAttr package pkgs)
      "managed stdio MCP command `${executable}` requires package `${package}`";
    "${pkgs.${package}}/bin/${executable}";

  render =
    pkgs: transport:
    if transport ? url then
      transport
    else
      let
        commandPaths = {
          mcp-searxng = packageExecutable pkgs "mcp-searxng" "mcp-searxng";
          mcp-server-sequential-thinking =
            packageExecutable pkgs "mcp-server-sequential-thinking"
              "mcp-server-sequential-thinking";
          nix-managed-mcp-stdio = packageExecutable pkgs "nix-managed-mcp-stdio" "nix-managed-mcp-stdio";
          pal-mcp-server = packageExecutable pkgs "pal-mcp-server" "pal-mcp-server";
          ssh = packageExecutable pkgs "openssh" "ssh";
        };
        resolveCommand =
          command:
          if lib.hasPrefix "/" command then
            command
          else if builtins.hasAttr command commandPaths then
            commandPaths.${command}
          else
            throw "managed stdio MCP command `${command}` has no immutable executable mapping";
        inheritedArguments = lib.concatMap inheritArgument (inheritedNamesFor transport);
        targetIndex = builtins.length inheritedArguments + 1;
        target = builtins.elemAt transport.args targetIndex;
      in
      assert lib.assertMsg (
        transport.command == "nix-managed-mcp-stdio"
      ) "managed stdio MCP transport bypassed its launcher";
      assert lib.assertMsg (
        builtins.elemAt transport.args (targetIndex - 1) == "--"
      ) "managed stdio MCP transport lost its target delimiter";
      transport
      // {
        command = commandPaths.nix-managed-mcp-stdio;
        args =
          lib.take targetIndex transport.args
          ++ [ (resolveCommand target) ]
          ++ lib.drop (targetIndex + 1) transport.args;
      };
in
{
  inherit
    normalize
    platformEnvironment
    render
    typedEnvironment
    ;
}
