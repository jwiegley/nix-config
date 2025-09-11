self: pkgs: with pkgs; {

bbcp = with pkgs; stdenv.mkDerivation rec {
  name = "bbcp-${version}";
  version = "64af8326";

  src = fetchFromGitHub {
    owner = "eeertekin";
    repo = "bbcp";
    rev = "64af83266da5ebb3fdc2f012ac7f5ce0230bc648";
    sha256 = "03d6w9mqlp4s651x7y9kphqgydr48q188km718fi0z2yc9m3yl4w";
    # date = 2016-05-02T14:04:09+03:00;
  };

  buildInputs = [
    zlib
    openssl
  ];

  patchPhase = ''
    substituteInPlace src/Makefile \
      --replace \
      'MACOPT     = $(SUN64) $(NLGR) -D_REENTRANT -DOO_STD -DMACOS -Wno-deprecated -g' \
      'MACOPT     = $(SUN64) $(NLGR) -D_REENTRANT -DOO_STD -DMACOS -Wno-register -Wno-c++11-narrowing -Wno-deprecated -g'
  '';
    
  buildPhase = ''
    cd src
    make MACCC=clang++ MACcc=clang -j $NIX_BUILD_CORES
    cd ..
  '';

  installPhase = ''
    mkdir -p $out/bin
    cp bin/_darwin_/bbcp $out/bin
  '';

  meta = with lib; {
    description = "Securely and quickly copy data from source to target.";
    homepage = https://github.com/eeertekin/bbcp;
    license = licenses.mit;
    maintainers = with maintainers; [ jwiegley ];
    platforms = platforms.unix;
  };
};

}
