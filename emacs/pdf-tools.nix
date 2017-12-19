{ stdenv, clang, gnumake, automake, autoconf, pkgconfig, libpng, zlib
, poppler }:

stdenv.mkDerivation rec {
  pname = "emacs-pdf-tools-server";
  version = "0.80";
  name = "${pname}-${version}";

  src = ~/emacs/site-lisp/pdf-tools/server;

  buildInputs = [
    clang gnumake automake autoconf pkgconfig libpng zlib poppler
  ];

  preConfigure = "./autogen.sh";

  installPhase = ''
    mkdir -p $out/bin
    cp -p epdfinfo $out/bin
  '';

  meta = with stdenv.lib; {
    homepage = https://github.com/politza/pdf-tools;
    description = "Emacs support library for PDF files";
    maintainers = with maintainers; [ jwiegley ];
    license = licenses.gpl3;
    platforms = platforms.unix;
  };
}
