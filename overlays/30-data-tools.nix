# overlays/30-data-tools.nix
# Purpose: Data processing and storage utilities
# Dependencies: prev.myLib (from 00-lib.nix) for tsvutils
# Packages: hashdb, dirscan, tsvutils
final: prev:

{

  # File checksum database for duplicate detection
  hashdb =
    with prev;
    python3Packages.buildPythonApplication {
      pname = "hashdb";
      version = "3586458b";

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
  dirscan = prev.inputs.dirscan.packages.${prev.stdenv.hostPlatform.system}.default;

}
// {

  # Utilities for processing tab-separated files
  tsvutils = prev.myLib.mkScriptPackage {
    name = "tsvutils-a286c817";
    src = prev.fetchFromGitHub {
      owner = "brendano";
      repo = "tsvutils";
      rev = "a286c8179342285803871834bb92c39cd52e516d";
      sha256 = "1jrg36ckvpmwjx9350lizfjghr3pfrmad0p3qibxwj14qw3wplni";
    };
    description = "Utilities for processing tab-separated files";
    homepage = "https://github.com/brendano/tsvutils";
  };

}
