_final: prev:
let
  gallery = import ../../packages/pi-gallery-packages.nix {
    inherit (prev)
      buildNpmPackage
      buildPackages
      chromium
      esbuild
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
    inherit (prev) inputs;
  };
in
gallery
// {
  agent-resources = prev.callPackage ../../packages/agent-resources.nix { };
}
