{
  pkgs,
  configured,
  inputs,
}:

let
  optionalMcpPackages = (import ../../overlays/ai/30-ai-mcp.nix { }) configured configured;
  aiPkgsWithout =
    inputName:
    import inputs.nixpkgs {
      system = pkgs.stdenv.hostPlatform.system;
      config.allowUnfree = true;
      overlays = import ../../overlays/ai {
        inputs = builtins.removeAttrs inputs [ inputName ];
      };
    };
  withoutPal = aiPkgsWithout "pal-mcp-server";
  withoutRemote = aiPkgsWithout "mcp-remote";
in
assert
  (configured.python3Packages.imageio.disabledTests or [ ])
  == (pkgs.python3Packages.imageio.disabledTests or [ ])
  || throw "Darwin-only imageio test suppression active on Linux";
assert
  (configured.python3Packages.gradio.doInstallCheck or false)
  == (pkgs.python3Packages.gradio.doInstallCheck or false)
  || throw "Darwin-only Gradio install-check suppression active on Linux";
assert
  !(optionalMcpPackages ? pal-mcp-server)
  && !(optionalMcpPackages ? agent-http-header-bridge)
  && optionalMcpPackages ? mcp-searxng
  || throw "optional MCP inputs must omit only their dependent packages";
assert
  !(withoutPal ? pal-mcp-server)
  && withoutPal ? agent-http-header-bridge
  && withoutPal ? mcp-searxng
  && withoutPal ? rustdocs-mcp-server
  || throw "missing PAL input removed unrelated AI MCP packages";
assert
  withoutRemote ? pal-mcp-server
  && !(withoutRemote ? agent-http-header-bridge)
  && withoutRemote ? mcp-searxng
  && withoutRemote ? rustdocs-mcp-server
  || throw "missing mcp-remote input removed unrelated AI MCP packages";
assert
  !(configured ? inputs) || throw "overlay composition leaked flake inputs through pkgs.inputs";
pkgs.runCommand "darwin-overrides-inactive" { } "touch $out"
