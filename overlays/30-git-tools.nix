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

  # go-git v5 lowercases extension names on read but the allowlist maps use
  # mixed case, so repos with `extensions.worktreeConfig=true` (left behind by
  # `git worktree` operations) fail the allowlist check. Patching the vendored
  # copy preserves the extension and lets tea read worktree-enabled repos.
  # Vendor tree is only materialized at configurePhase, so patch in preBuild.
  tea = prev.tea.overrideAttrs (old: {
    preBuild = (old.preBuild or "") + ''
      chmod -R u+w vendor/github.com/go-git/go-git/v5
      substituteInPlace vendor/github.com/go-git/go-git/v5/repository_extensions.go \
        --replace-fail '"worktreeConfig":  {},' '"worktreeconfig":  {},'
      substituteInPlace vendor/github.com/go-git/go-git/v5/repository_extensions.go \
        --replace-fail '"noop-v1": {},' \
        $'"noop-v1": {},\n\t\t"worktreeconfig": {},'
    '';
  });

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
