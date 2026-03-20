# overlays/30-data-tools.nix
# Purpose: Data processing and storage utilities
# Dependencies: None (uses only prev)
# Packages: hashdb, dirscan, tsvutils
final: prev:

{

  # File checksum database for duplicate detection
  hashdb =
    with prev;
    python3Packages.buildPythonApplication {
      pname = "hashdb";
      version = "0.1.0";

      src = fetchFromGitHub {
        owner = "jwiegley";
        repo = "hashdb";
        rev = "3586458b01e7f61c6254d9a5220fc2fa6b4d217e";
        sha256 = "sha256-nu4TMw3Jn1HEVqH244JovG8zN6CbgMg3TC/T0We59l8=";
      };

      pyproject = true;
      build-system = [ python3Packages.setuptools ];

      meta = {
        homepage = "https://github.com/jwiegley/hashdb";
        description = "File checksum database for duplicate detection";
        license = lib.licenses.bsd3;
        maintainers = with lib.maintainers; [ jwiegley ];
      };
    };

}
// prev.lib.optionalAttrs (prev ? inputs && prev.inputs ? dirscan) {

  # Stateful directory scanning utility (from dirscan flake)
  dirscan = prev.inputs.dirscan.packages.${prev.system}.default;

}
// {

  # Utilities for processing tab-separated files
  tsvutils =
    with prev;
    stdenv.mkDerivation rec {
      name = "tsvutils-${version}";
      version = "a286c817";

      src = fetchFromGitHub {
        owner = "brendano";
        repo = "tsvutils";
        rev = "a286c8179342285803871834bb92c39cd52e516d";
        sha256 = "1jrg36ckvpmwjx9350lizfjghr3pfrmad0p3qibxwj14qw3wplni";
        # date = 2019-08-11T16:06:16-04:00;
      };

      phases = [
        "unpackPhase"
        "installPhase"
      ];

      installPhase = ''
        mkdir -p $out/bin
        find . -maxdepth 1 \( -type f -o -type l \) -executable \
            -exec cp -pL {} $out/bin \;
      '';

      meta = with prev.lib; {
        description = "Utilities for processing tab-separated files";
        homepage = "https://github.com/brendano/tsvutils";
        license = licenses.mit;
        maintainers = with maintainers; [ jwiegley ];
        platforms = platforms.unix;
      };
    };

}
