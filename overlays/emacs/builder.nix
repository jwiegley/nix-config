{ stdenv
, emacs
, name
, src
, buildInputs ? []
, patches ? []
}:

stdenv.mkDerivation {
  inherit name src patches;
  unpackCmd = ''
    test -f "${src}" && mkdir el && cp -p ${src} el/${name}
  '';
  buildInputs = [ emacs ] ++ buildInputs;
  buildPhase = ''
    ARGS=$(find ${stdenv.lib.concatStrings
                  (builtins.map (arg: arg + "/share/emacs/site-lisp ") buildInputs)} \
                 -type d -exec echo -L {} \;)
    ${emacs}/bin/emacs -Q -nw -L . $ARGS --batch -f batch-byte-compile *.el
  '';
  installPhase = ''
    mkdir -p $out/share/emacs/site-lisp
    install *.el* $out/share/emacs/site-lisp
  '';
  meta = {
    description = "Emacs projects from the Internet that just compile .el files";
    homepage = http://www.emacswiki.org;
    platforms = stdenv.lib.platforms.all;
  };
}
