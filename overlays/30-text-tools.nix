# overlays/30-text-tools.nix
# Purpose: Text processing and org-mode related tools
# Dependencies: prev, tools source catalog, optional org2tc input
# Packages: filetags, hyperorg, org2tc
# Notes:
#   - hyperorg uses ./emacs/patches/hyperorg.patch
#   - org2tc requires org2tc
{
  org2tc ? null,
}:
_final: prev:

let
  sources = import ../packages/source-catalog.nix "tools";
in
{

  # Manage tags in filenames
  filetags =
    with prev;
    with python3Packages;
    buildPythonPackage rec {
      pname = "filetags";
      inherit (sources.filetags) version;
      name = "${pname}-${version}";
      pyproject = false;

      src =
        assert sources.filetags.source.fetcher == "fetchFromGitHub";
        fetchFromGitHub sources.filetags.source.args;

      propagatedBuildInputs = [
        colorama
        clint
      ];

      installPhase = ''
        mkdir -p $out/bin
        cp -p filetags/__init__.py $out/bin/filetags
        chmod +x $out/bin/filetags
      '';

      meta = {
        homepage = "https://github.com/novoid/filetags";
        description = "Management of simple tags within file names.";
        license = lib.licenses.gpl3;
        maintainers = with lib.maintainers; [ jwiegley ];
      };
    };

  # Convert org-mode/org-roam files to HTML
  hyperorg =
    with prev;
    with python3Packages;
    buildPythonPackage {
      pname = "hyperorg";
      inherit (sources.hyperorg) version;
      pyproject = true;

      src =
        assert sources.hyperorg.source.fetcher == "fetchgit";
        fetchgit sources.hyperorg.source.args;

      patches = [ ./emacs/patches/hyperorg.patch ];

      build-system = [
        setuptools
        setuptools-scm
      ];

      dependencies = [
        setuptools
        orgparse
        python-dateutil
        packaging
        requests
      ];

      meta = {
        homepage = "https://codeberg.org/buhtz/hyperorg";
        description = "Hyperorg converts org-files and especially orgroam-v2-files into html-files.";
        license = lib.licenses.mit;
        maintainers = with lib.maintainers; [ jwiegley ];
      };
    };

}
// prev.lib.optionalAttrs (org2tc != null) {

  # Convert org-mode to timeclock format
  # Note: Requires org2tc
  org2tc =
    with prev;
    stdenv.mkDerivation rec {
      name = "org2tc-${version}";
      version = builtins.substring 0 7 org2tc.rev;

      src = org2tc;

      phases = [
        "unpackPhase"
        "installPhase"
      ];

      installPhase = ''
        mkdir -p $out/bin
        cp -p org2tc $out/bin
      '';

      meta = with prev.lib; {
        description = "Conversion utility from Org-mode to timeclock format";
        homepage = "https://github.com/jwiegley/org2tc";
        license = licenses.mit;
        maintainers = with maintainers; [ jwiegley ];
        platforms = platforms.unix;
      };
    };

}
