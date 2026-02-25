# overlays/30-text-tools.nix
# Purpose: Text processing and org-mode related tools
# Dependencies: None (uses only prev)
# Packages: filetags, hyperorg, org2tc
# Notes:
#   - hyperorg uses ./emacs/patches/hyperorg.patch
#   - org2tc requires paths.org2tc
final: prev:

let
  paths = import ../config/paths.nix { inherit (prev) inputs; };
in
{

  # Manage tags in filenames
  filetags =
    with prev;
    with python3Packages;
    buildPythonPackage rec {
      pname = "filetags";
      version = "b68a731c";
      name = "${pname}-${version}";
      pyproject = false;

      src = fetchFromGitHub {
        owner = "novoid";
        repo = "filetags";
        rev = "b68a731c815c1e4c96ed7b1c3a3b32cf92008943";
        sha256 = "sha256-zHLMQgxKhlmae+td8RycHH1I49SZ8dzpvO3uwUXVyKw=";
        # date = "2025-09-15T13:27:03+02:00";
      };

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
    buildPythonPackage rec {
      pname = "hyperorg";
      version = "a814c4bf5e";
      pyproject = true;

      src = fetchgit {
        url = "https://codeberg.org/buhtz/hyperorg.git";
        rev = "f9fc6a164cd94df4d146c69fc7e48aeb143afe16";
        sha256 = "0cr16p6z0spr9xdabw4da77hrsmn4dzvfxd15kllva8w28xqsbl6";
        # date = 2025-08-31T09:48:06+02:00;
      };

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

  # Convert org-mode to timeclock format
  # Note: Requires paths.org2tc
  org2tc =
    with prev;
    stdenv.mkDerivation rec {
      name = "org2tc-${version}";
      version = "7d52a20";

      src = paths.org2tc;

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
