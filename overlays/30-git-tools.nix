# overlays/30-git-tools.nix
# Purpose: Git-related tools and extensions
# Dependencies: prev.myLib, tools source catalog, optional gitScripts input
# Packages: tea, git-branchstack, git-scripts
# Note: git-scripts requires gitScripts
{
  gitScripts ? null,
}:
_final: prev:

let
  sources = import ../packages/source-catalog.nix "tools";
in
{

  # Tea before 0.15 used go-git v5, which lowercases extension names on read
  # while the allowlist maps use mixed case. Patch its vendored copy so repos
  # with extensions.worktreeConfig=true remain readable.
  tea =
    if prev.lib.versionOlder prev.tea.version "0.15.0" then
      prev.tea.overrideAttrs (old: {
        preBuild = (old.preBuild or "") + ''
          chmod -R u+w vendor/github.com/go-git/go-git/v5
          substituteInPlace vendor/github.com/go-git/go-git/v5/repository_extensions.go \
            --replace-fail '"worktreeConfig":  {},' '"worktreeconfig":  {},'
          substituteInPlace vendor/github.com/go-git/go-git/v5/repository_extensions.go \
            --replace-fail '"noop-v1": {},' \
            $'"noop-v1": {},\n\t\t"worktreeconfig": {},'
        '';
      })
    else
      # Tea 0.15 switched to a native Git CLI backend with worktree coverage.
      prev.tea;

  # Build the catalog-pinned git-branchstack source and relax its git-revise
  # metadata constraint.
  git-branchstack = prev.git-branchstack.overrideAttrs (old: {
    inherit (sources.git-branchstack) version;
    src =
      assert sources.git-branchstack.source.fetcher == "fetchFromGitHub";
      prev.fetchFromGitHub sources.git-branchstack.source.args;
    pythonRelaxDeps = (old.pythonRelaxDeps or [ ]) ++ [ "git-revise" ];
  });

}
// prev.lib.optionalAttrs (gitScripts != null) {

  git-scripts = prev.myLib.mkScriptPackage {
    name = "git-scripts";
    src = gitScripts;
    description = "John Wiegley's git scripts";
    homepage = "https://github.com/jwiegley/git-scripts";
    # The locked source declares no repository-wide license.
    license = prev.lib.licenses.unfree;
    excludeFiles = [ "git-merge-changelog" ];
  };

}
