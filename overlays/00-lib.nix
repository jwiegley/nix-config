# overlays/00-lib.nix
# Purpose: Shared helper functions for overlay definitions.
# Exposes pkgs.myLib.{mkScriptPackage, mkSimpleGitHubBinary}.
# Loaded early (00-) so later overlays can access prev.myLib.
_final: prev:
let
  inherit (prev) lib stdenv fetchFromGitHub;
in
{
  myLib = (prev.myLib or { }) // {

    # Package a directory of executable scripts (or symlinks) into $out/bin.
    # `src` may be a local path or a fetched tarball — anything unpackPhase
    # can handle. `includeFiles` selects an exact public surface; otherwise,
    # `excludeFiles` removes known non-public files. `extraInstall` runs after
    # the copy (e.g. to rewrite shebangs).
    mkScriptPackage =
      {
        name,
        src,
        description,
        license,
        homepage ? "https://github.com/jwiegley",
        includeFiles ? null,
        excludeFiles ? [ ],
        extraInstall ? "",
      }:
      let
        excludeArgs = lib.concatMapStringsSep " " (f: "! -name ${lib.escapeShellArg f}") excludeFiles;
      in
      assert includeFiles == null || excludeFiles == [ ];
      stdenv.mkDerivation {
        inherit name src;
        phases = [
          "unpackPhase"
          "installPhase"
        ];
        installPhase = ''
          mkdir -p $out/bin
          ${
            if includeFiles == null then
              ''
                find . -maxdepth 1 \( -type f -o -type l \) -executable ${excludeArgs} \
                    -exec cp -pL {} $out/bin \;
              ''
            else
              ''
                for file in ${lib.escapeShellArgs includeFiles}; do
                  test -x "$file"
                  cp -pL -- "$file" $out/bin/
                done
              ''
          }
          ${extraInstall}
        '';
        meta = {
          inherit description homepage license;
          maintainers = with lib.maintainers; [ jwiegley ];
          platforms = lib.platforms.unix;
        };
      };

    # Copy one binary or interpreted script from a catalog-owned GitHub source
    # to $out/bin. `binName` defaults to `pname`; source trees needing a build
    # step use mkDerivation, while script directories use mkScriptPackage.
    mkSimpleGitHubBinary =
      args@{
        pname,
        source,
        description,
        ...
      }:
      let
        inherit (source) version;
        owner = source.source.args.owner;
        repo = source.source.args.repo;
        binName = args.binName or pname;
        homepage = args.homepage or "https://github.com/${owner}/${repo}";
        license = args.license or lib.licenses.mit;
      in
      stdenv.mkDerivation {
        name = "${pname}-${version}";
        inherit version;
        src =
          assert source.source.fetcher == "fetchFromGitHub";
          fetchFromGitHub source.source.args;
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
