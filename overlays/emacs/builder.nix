{ stdenv, pkgs, emacs, name, src, buildInputs ? [ ], propagatedBuildInputs ? [ ]
, patches ? [ ], preBuild ? "" }:

stdenv.mkDerivation {
  inherit name src patches propagatedBuildInputs;
  unpackCmd = ''
    test -f "${src}" && mkdir el && cp -p ${src} el/${name}
  '';
  buildInputs = [ emacs ] ++ buildInputs;
  buildPhase = ''
    ${preBuild}
    set -x
    ARGS=$(find ${
      pkgs.lib.concatStrings
      (builtins.map (arg: arg + "/share/emacs/site-lisp ") buildInputs)
    } \
                 -type d -exec echo -L {} \;)
    mkdir $out
    export HOME=$out
    if ${emacs}/bin/emacs --version | grep 29; then
        ${emacs}/bin/emacs -Q -nw -L . $ARGS --batch -f batch-byte-compile *.el
    else
        ${emacs}/bin/emacs -Q -nw -L . $ARGS --batch --eval "(setq byte-compile-warnings '(not docstrings))" -f batch-byte-compile *.el
    fi
  '';
  installPhase = ''
    mkdir -p $out/share/emacs/site-lisp
    install *.el* $out/share/emacs/site-lisp
  '';
  meta = {
    description =
      "Emacs projects from the Internet that just compile .el files";
    homepage = "http://www.emacswiki.org";
    platforms = pkgs.lib.platforms.all;
  };
}
