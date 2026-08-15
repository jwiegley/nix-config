{
  inputs,
  pkgs,
}:

let
  gitAll = pkgs.haskellPackages.git-all;
in
{
  # Build source-only application inputs with the host package set. This avoids
  # evaluating their complete flakes for foreign systems.
  git-all =
    assert gitAll.version == "1.8.1";
    pkgs.haskell.lib.justStaticExecutables (
      pkgs.haskell.lib.overrideSrc gitAll {
        src = inputs.git-all.outPath;
      }
    );
}
