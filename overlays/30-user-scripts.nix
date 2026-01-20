# overlays/30-user-scripts.nix
# Purpose: Personal script collections
# Dependencies: Uses final for perl and haskellPackages (cross-overlay reference)
# Packages: nix-scripts, my-scripts
# Notes:
#   - nix-scripts from this repository's bin/ directory
#   - my-scripts requires paths.scripts
final: prev:

let paths = import ../config/paths.nix;
in {

  # Scripts from this repository's bin/ directory
  nix-scripts = with prev;
    stdenv.mkDerivation {
      name = "nix-scripts";

      src = ../bin;

      buildInputs = [ ];

      installPhase = ''
        mkdir -p $out/bin
        find . -maxdepth 1 \( -type f -o -type l \) -executable \
            -exec cp -pL {} $out/bin \;
      '';

      meta = with prev.lib; {
        description = "Nix configuration scripts";
        homepage = "https://github.com/jwiegley";
        license = licenses.mit;
        maintainers = with maintainers; [ jwiegley ];
        platforms = platforms.darwin;
      };
    };

  # Personal scripts collection
  # Note: Requires paths.scripts
  my-scripts = with final;
    stdenv.mkDerivation {
      name = "my-scripts";

      src = builtins.filterSource
        (path: type: type != "directory" || baseNameOf path != ".git")
        paths.scripts;

      buildInputs = [ ];

      installPhase = ''
        mkdir -p $out/bin
        find . -maxdepth 1 \( -type f -o -type l \) -executable \
            -exec cp -pL {} $out/bin \;
        ${final.perl}/bin/perl -i -pe \
            's^#!/usr/bin/env runhaskell^#!${final.haskellPackages.ghc}/bin/runhaskell^;' $out/bin/*
      '';

      meta = with prev.lib; {
        description = "John Wiegley's various scripts";
        homepage = "https://github.com/jwiegley";
        license = licenses.mit;
        maintainers = with maintainers; [ jwiegley ];
        platforms = platforms.darwin;
      };
    };

}
