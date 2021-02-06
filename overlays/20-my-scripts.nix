self: super: {

my-scripts = with self; stdenv.mkDerivation {
  name = "my-scripts";

  src = builtins.filterSource (path: type:
      type != "directory" || baseNameOf path != ".git")
    ~/src/scripts;

  buildInputs = [];

  installPhase = ''
    mkdir -p $out/bin
    find . -maxdepth 1 \( -type f -o -type l \) -executable \
        -exec cp -pL {} $out/bin \;
    ${self.perl}/bin/perl -i -pe \
        's^#!/usr/bin/env runhaskell^#!${self.haskellPackages.ghc}/bin/runhaskell^;' $out/bin/*
  '';

  meta = with pkgs.lib; {
    description = "John Wiegley's various scripts";
    homepage = https://github.com/jwiegley;
    license = licenses.mit;
    maintainers = with maintainers; [ jwiegley ];
    platforms = platforms.darwin;
  };
};

}
