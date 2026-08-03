{ inputs }:
_final: prev:
let
  gallery = import ../../packages/pi-gallery {
    inherit (prev)
      buildNpmPackage
      buildPackages
      chromium
      esbuild
      fetchFromGitHub
      fetchurl
      findutils
      jq
      lib
      makeWrapper
      patchelf
      playwright-driver
      python3
      runCommand
      stdenv
      writeShellScript
      ;
    inherit inputs;
  };
in
gallery
// {
  agent-resources = prev.callPackage ../../packages/agent-resources.nix { inherit inputs; };
}
