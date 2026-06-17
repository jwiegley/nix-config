# config/overlays.nix
# Shared overlay list for both Darwin and standalone home-manager configurations.
#
# Usage:
#   overlays = import ./config/overlays.nix { inherit inputs; };
#   (from config/ directory: import ./overlays.nix { inherit inputs; };)

{
  inputs,
  # Optional: path to the Vulcan private root CA. Only available on hosts
  # that have local access to the certificate file (i.e. hera, clio, vulcan).
  # Remote consumers of this repo (andoria, ovh-vps) pass `null` and skip the
  # merged-bundle overlay; vars.nix falls back to plain cacert in that case.
  vulcan-crt ? null,
}:

assert
  inputs ? ai-nix
  || builtins.throw ''
    nix-config now expects an `ai-nix` flake input.

    Add it to the consuming flake, for example:

      ai-nix = {
        url = "github:jwiegley/ai-nix";
        inputs.nixpkgs.follows = "nixpkgs";
      };
  '';

let
  overlayDir = ../overlays;
  isImportableOverlay =
    n:
    builtins.match ".*\\.nix" n != null
    || builtins.pathExists (overlayDir + ("/" + n + "/default.nix"));
in
[
  inputs.ai-nix.overlays.default
  # Restore this flake's inputs after ai-nix applies its own overlay stack.
  (_final: _prev: { inherit inputs; })
]
++ (
  # A merged CA bundle (system roots + Vulcan's private root CA), built as a
  # standalone derivation rather than overriding `cacert` itself. Overriding
  # `cacert` rebuilds curl/openssl/git/python/node and every fixed-output
  # derivation in the closure for what is purely runtime data. Only included
  # when vulcan-crt is provided; otherwise vars.nix falls back to cacert.
  if vulcan-crt == null then
    [ ]
  else
    [
      (_final: prev: {
        ca-bundle-with-vulcan = prev.runCommand "ca-bundle-with-vulcan" { } ''
          mkdir -p $out/etc/ssl/certs
          cat ${prev.cacert}/etc/ssl/certs/ca-bundle.crt ${vulcan-crt} \
            > $out/etc/ssl/certs/ca-bundle.crt
        '';
      })
    ]
)
++ (
  with builtins;
  map (n: import (overlayDir + ("/" + n))) (
    filter isImportableOverlay (attrNames (readDir overlayDir))
  )
)
