self: super: {

# pdf-tools-server = with self; super.stdenv.mkDerivation rec {
#   pname = "emacs-pdf-tools-server";
#   version = "0.80";
#   name = "${pname}-${version}";

#   src = super.fetchFromGitHub {
#     owner = "politza";
#     repo = "pdf-tools";
#     rev = "cc29d4c9c2d81fcb1255f7172fd5b9b7851d656c";
#     sha256 = "0833x6q048sym8jlc7fhi2ypsdc1vgiy5b6ijg4wgsnskg91nyva";
#     # date = 2019-12-28T11:05:12+01:00;
#   };

#   buildInputs = [
#     clang gnumake automake autoconf pkgconfig libpng zlib poppler
#   ];

#   patches = [ ./emacs/patches/pdf-tools.patch ];

#   preConfigure = ''
#     cd server
#     ./autogen.sh
#   '';

#   installPhase = ''
#     echo hello
#     mkdir -p $out/bin
#     cp -p epdfinfo $out/bin
#   '';

#   meta = with stdenv.lib; {
#     homepage = https://github.com/politza/pdf-tools;
#     description = "Emacs support library for PDF files";
#     maintainers = with maintainers; [ jwiegley ];
#     license = licenses.gpl3;
#     platforms = platforms.unix;
#   };
# };

}
