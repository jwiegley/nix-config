# overlays/30-git-tools.nix
# Purpose: Git-related tools and extensions
# Dependencies: None (uses only prev)
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

}
// prev.lib.optionalAttrs (paths.git-scripts != null) {

  # Custom git helper scripts
  # Note: Requires paths.git-scripts
  git-scripts =
    with prev;
    stdenv.mkDerivation {
      name = "git-scripts";

      src = paths.git-scripts;

      buildInputs = [ ];

      installPhase = ''
        mkdir -p $out/bin
        find . -maxdepth 1 \( -type f -o -type l \) -executable \
            ! -name git-merge-changelog \
            -exec cp -pL {} $out/bin \;
      '';

      meta = with prev.lib; {
        description = "John Wiegley's git scripts";
        homepage = "https://github.com/jwiegley/git-scripts";
        license = licenses.mit;
        maintainers = with maintainers; [ jwiegley ];
        platforms = platforms.unix;
      };
    };

}
