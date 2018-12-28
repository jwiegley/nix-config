self: super: {

pdf-tools-server = with self; super.stdenv.mkDerivation rec {
  pname = "emacs-pdf-tools-server";
  version = "0.80";
  name = "${pname}-${version}";

  src = super.fetchFromGitHub {
    owner = "politza";
    repo = "pdf-tools";
    rev = "a4cd69ea1d50b8e74ea515eec95948ad87c6c732";
    sha256 = "0m9hwihj2n8vv7hmcg6ax5sjxlmsb7wgsd6wqkp01x1xb5qjqhpm";
    # date = 2018-12-21T20:13:05+01:00;
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
