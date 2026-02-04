# overlays/30-data-tools.nix
# Purpose: Data processing and storage utilities
# Dependencies: None (uses only prev)
# Packages: hashdb, dirscan, tsvutils
# Note: dirscan requires paths.dirscan
final: prev:

let paths = import ../config/paths.nix { inherit (prev) inputs; };
in {

  # Simple key/value store for keeping hashes
  hashdb = with prev;
    stdenv.mkDerivation rec {
      name = "hashdb-${version}";
      version = "86c8675d";

      src = fetchFromGitHub {
        owner = "jwiegley";
        repo = "hashdb";
        rev = "86c8675d4116c03e81a7468cc66c4c987f1d203e";
        sha256 = "sha256-rs0eqy8yA2YXZd1y6djGIG/WFwvWlSfz08m5qlkG524=";
        # date = 2011-10-04T03:27:40-05:00;
      };

      phases = [ "unpackPhase" "installPhase" ];

      installPhase = ''
        mkdir -p $out/bin
        cp -p hashdb $out/bin
      '';

      meta = {
        homepage = "https://github.com/jwiegley/hashdb";
        description = "A simply key/value store for keeping hashes";
        license = lib.licenses.mit;
        maintainers = with lib.maintainers; [ jwiegley ];
      };
    };

  # Stateful directory scanning utility
  # Note: Requires paths.dirscan
  dirscan = with prev;
    python3Packages.buildPythonPackage rec {
      pname = "dirscan";
      version = "2.0";
      format = "source";

      src = paths.dirscan;

      phases = [ "unpackPhase" "installPhase" ];

      installPhase = ''
        mkdir -p $out/bin $out/libexec
        cp dirscan.py $out/libexec
        python -mpy_compile $out/libexec/dirscan.py
        cp cleanup $out/bin
      '';

      meta = {
        homepage = "https://github.com/jwiegley/dirscan";
        description = "Stateful directory scanning in Python";
        license = lib.licenses.mit;
        maintainers = with lib.maintainers; [ jwiegley ];
      };
    };

  # Utilities for processing tab-separated files
  tsvutils = with prev;
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

      phases = [ "unpackPhase" "installPhase" ];

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
