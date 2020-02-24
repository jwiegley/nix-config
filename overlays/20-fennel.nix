self: super: {

fennel = with super; stdenv.mkDerivation rec {
  name = "fennel-${version}";
  version = "ea4ec851";

  src = fetchFromGitHub {
    owner = "bakpakin";
    repo = "Fennel";
    rev = "ea4ec851eb0f4ded0c7d31d169f3aa2b3df8592b";
    sha256 = "1b4760sqpbdjz0k6qr4a8i2jvkgnjhdlpf4qwy1p28nz9zsnjw2j";
    # date = 2020-02-13T19:49:49-08:00;
  };

  propagatedBuildInputs = [ lua ];

  installPhase = ''
    mkdir -p $out/bin $out/share/man/man1
    cp fennel $out/bin
    cp fennel.1 $out/share/man/man1
  '';

  meta = with stdenv.lib; {
    description = ''
      Fennel is a lisp that compiles to Lua. It aims to be easy to use,
      expressive, and has almost zero overhead compared to handwritten Lua.
    '';
    homepage = https://fennel-lang.org;
    license = licenses.mit;
    maintainers = with maintainers; [ jwiegley ];
    platforms = platforms.unix;
  };
};

}
