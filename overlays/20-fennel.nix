self: super: {

fennel = with super; stdenv.mkDerivation rec {
  name = "fennel-${version}";
  version = "1abi8hmr";

  src = fetchFromGitHub {
    owner = "bakpakin";
    repo = "Fennel";
    rev = "ded00cf3933ea4435f5be95be071653c8ea42087";
    sha256 = "1abi8hmrpv73kv25dibgacmpg4a3nl8l0753djwvx6ds6x1a9bsy";
    # date = 2020-01-15T17:18:25-08:00;
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
