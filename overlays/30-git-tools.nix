# overlays/30-git-tools.nix
# Purpose: Git-related tools and extensions
# Dependencies: prev.myLib (from 00-lib.nix) for git-scripts
# Packages: tea (patched), git-scripts (local source)
# Note: git-scripts requires paths.git-scripts
final: prev:

let
  paths = import ../config/paths.nix { inherit (prev) inputs; };
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
      sed -i 's|"noop-v1": {},|&\n\t\t"worktreeconfig": {},|' \
        vendor/github.com/go-git/go-git/v5/repository_extensions.go
    '';
  });

  # git-branchstack 0.2.0 (PyPI, Jan 2022 -- upstream's last release) pins
  # git-revise==0.7.0, which the 2026-07-05 nixpkgs bump broke by moving
  # python3Packages.git-revise to 0.8.0 (pythonRuntimeDepsCheckHook rejects
  # the wheel). The 0.2.0 release also lacks upstream's bec4034 fix for a
  # runtime ValueError with any git-revise carrying the editor-cwd change
  # (git-revise#118), which 0.8.0 does. Build from upstream master (has the
  # fix, still pins ==0.7.0 in setup.py) and relax the pin. Drop this if
  # upstream ever cuts a release and nixpkgs picks it up.
  git-branchstack = prev.git-branchstack.overrideAttrs (old: {
    version = "0.2.0-unstable-2025-02-07";
    src = prev.fetchFromGitHub {
      owner = "krobelus";
      repo = "git-branchstack";
      rev = "94563ec53ead302a3eca9edccfafa0af6c3c43c0";
      hash = "sha256-d8PQTxkPOHA/OE085dGTnI8tJmiac5f8Q7VHirQ6Yho=";
    };
    pythonRelaxDeps = (old.pythonRelaxDeps or [ ]) ++ [ "git-revise" ];
  });

}
// prev.lib.optionalAttrs (paths.git-scripts != null) {

  git-scripts = prev.myLib.mkScriptPackage {
    name = "git-scripts";
    src = paths.git-scripts;
    description = "John Wiegley's git scripts";
    homepage = "https://github.com/jwiegley/git-scripts";
    excludeFiles = [ "git-merge-changelog" ];
  };

}
