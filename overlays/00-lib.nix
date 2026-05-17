# overlays/00-lib.nix
# Purpose: Shared helper functions for overlay definitions.
# Exposes pkgs.myLib.{mkScriptPackage, mkSimpleGitHubBinary}.
# Loaded early (00-) so later overlays can access prev.myLib.
final: prev:
let
  inherit (prev) lib stdenv fetchFromGitHub;
in
{
  myLib = (prev.myLib or { }) // {

    # Package a directory of executable scripts (or symlinks) into $out/bin.
    # `src` may be a local path or a fetched tarball — anything unpackPhase
    # can handle. Files listed in `excludeFiles` are skipped. `extraInstall`
    # runs after the copy (e.g. to rewrite shebangs).
    mkScriptPackage =
      {
        name,
        src,
        description,
        homepage ? "https://github.com/jwiegley",
        license ? lib.licenses.mit,
        excludeFiles ? [ ],
        extraInstall ? "",
      }:
      let
        excludeArgs = lib.concatMapStringsSep " " (f: "! -name ${lib.escapeShellArg f}") excludeFiles;
      in
      stdenv.mkDerivation {
        inherit name src;
        phases = [
          "unpackPhase"
          "installPhase"
        ];
        installPhase = ''
          mkdir -p $out/bin
          find . -maxdepth 1 \( -type f -o -type l \) -executable ${excludeArgs} \
              -exec cp -pL {} $out/bin \;
          ${extraInstall}
        '';
        meta = {
          inherit description homepage license;
          maintainers = with lib.maintainers; [ jwiegley ];
          platforms = lib.platforms.unix;
        };
      };

    # Fetch a single-binary (typically interpreted script) from GitHub and
    # copy it to $out/bin. Defaults `owner` to "jwiegley" and `repo`/`binName`
    # to `pname`. For source trees that need a build step, use mkDerivation
    # directly; for directories of scripts use mkScriptPackage.
    mkSimpleGitHubBinary =
      args@{
        pname,
        version,
        rev,
        sha256,
        description,
        ...
      }:
      let
        owner = args.owner or "jwiegley";
        repo = args.repo or pname;
        binName = args.binName or pname;
        homepage = args.homepage or "https://github.com/${owner}/${repo}";
        license = args.license or lib.licenses.mit;
      in
      stdenv.mkDerivation {
        name = "${pname}-${version}";
        inherit version;
        src = fetchFromGitHub {
          inherit
            owner
            repo
            rev
            sha256
            ;
        };
        phases = [
          "unpackPhase"
          "installPhase"
        ];
        installPhase = ''
          mkdir -p $out/bin
          cp -p ${binName} $out/bin
        '';
        meta = {
          inherit description homepage license;
          maintainers = with lib.maintainers; [ jwiegley ];
        };
      };
  };
}
