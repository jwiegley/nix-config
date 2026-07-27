# Cross-platform Eask package, independent of Darwin compatibility pins.
_final: prev:
let
  source = (import ../packages/source-catalog.nix "tools").eask-cli;
in
{
  eask-cli = prev.buildNpmPackage rec {
    pname = "eask-cli";
    inherit (source) version;
    src =
      assert source.source.fetcher == "fetchFromGitHub";
      prev.fetchFromGitHub source.source.args;
    npmDepsHash = source.hashes.npmDepsHash;
    dontBuild = true;
    meta = with prev.lib; {
      description = "CLI for building, running, testing, and managing Emacs Lisp dependencies";
      homepage = "https://emacs-eask.github.io/";
      license = licenses.gpl3Plus;
      mainProgram = "eask";
    };
  };
}
