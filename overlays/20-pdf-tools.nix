self: super: {

pdf-tools-server = with self; super.stdenv.mkDerivation rec {
  pname = "emacs-pdf-tools-server";
  version = "0.80";
  name = "${pname}-${version}";

  src = super.fetchFromGitHub {
    owner = "politza";
    repo = "pdf-tools";
    rev = "60d12ce15220d594e8eb95f4d072e2710cddefe0";
    sha256 = "1s8zphbd7k1ifdlisy894cg4mrkiq1rl2qk8x10njp1i596hz1fm";
    # date = 2018-04-29T18:31:04+02:00;
  };

  buildInputs = [
    clang gnumake automake autoconf pkgconfig libpng zlib poppler
  ];

  patches = [ ./emacs/patches/pdf-tools.patch ];

  preConfigure = ''
    cd server
    ./autogen.sh
  '';

  installPhase = ''
    echo hello
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
};

}
