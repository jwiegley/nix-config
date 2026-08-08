{ bunNixpkgs }:
_final: prev: {
  cm = prev.callPackage ../../packages/cm.nix {
    cmBun = bunNixpkgs.legacyPackages.${prev.stdenv.hostPlatform.system}.bun;
  };
}
