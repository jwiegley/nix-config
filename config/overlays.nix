# config/overlays.nix
# Shared overlay list for both Darwin and standalone home-manager configurations.
#
# Usage:
#   overlays = import ./config/overlays.nix { inherit inputs; };
#   (from config/ directory: import ./overlays.nix { inherit inputs; };)

{ inputs }:

let
  overlayDir = ../overlays;
in
[
  # Inject flake inputs so overlays can access them via prev.inputs
  (final: prev: { inherit inputs; })

  inputs.mcp-servers-nix.overlays.default

  (final: prev: {
    github-mcp-server =
      prev.callPackage (import "${inputs.nixpkgs}/pkgs/by-name/gi/github-mcp-server/package.nix")
        { };
  })
]
++ (
  with builtins;
  map (n: import (overlayDir + ("/" + n))) (
    filter (n: match ".*\\.nix" n != null || pathExists (overlayDir + ("/" + n + "/default.nix"))) (
      attrNames (readDir overlayDir)
    )
  )
)
