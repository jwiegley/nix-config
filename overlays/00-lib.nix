# overlays/00-lib.nix
# Purpose: Shared utility functions for other overlays
# Dependencies: None (foundation layer)
# Provides: myLib.mkScriptPackage, myLib.mkSimpleGitHubPackage
final: prev: {

  myLib = {
    # Build a package from a directory of executable scripts
    # Used by: nix-scripts, my-scripts, git-scripts
    mkScriptPackage = {
      name,
      src,
      extraInstallPhase ? "",
      description ? "Script collection",
      homepage ? "https://github.com/jwiegley",
      license ? prev.lib.licenses.mit,
      platforms ? prev.lib.platforms.darwin
    }:
      prev.stdenv.mkDerivation {
        inherit name src;
        buildInputs = [ ];
        installPhase = ''
          mkdir -p $out/bin
          find . -maxdepth 1 \( -type f -o -type l \) -executable \
              -exec cp -pL {} $out/bin \;
          ${extraInstallPhase}
        '';
        meta = {
          inherit description homepage license platforms;
          maintainers = with prev.lib.maintainers; [ jwiegley ];
        };
      };

    # Build a simple package from a GitHub repository
    # Used by: hammer, hashdb, linkdups, lipotell, sift, sshify, etc.
    mkSimpleGitHubPackage = {
      name,
      version,
      owner,
      repo,
      rev,
      sha256,
      executable ? name,
      installDir ? "bin",
      description,
      homepage ? "https://github.com/${owner}/${repo}",
      license ? prev.lib.licenses.mit
    }:
      prev.stdenv.mkDerivation {
        name = "${name}-${version}";
        src = prev.fetchFromGitHub {
          inherit owner repo rev sha256;
        };
        phases = [ "unpackPhase" "installPhase" ];
        installPhase = ''
          mkdir -p $out/${installDir}
          cp -p ${executable} $out/${installDir}/
        '';
        meta = {
          inherit description homepage license;
          maintainers = with prev.lib.maintainers; [ jwiegley ];
        };
      };

    # Filter out .git directory from source
    filterGitSource = src:
      builtins.filterSource
        (path: type: type != "directory" || baseNameOf path != ".git")
        src;
  };

}
