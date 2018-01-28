self: super: {

sift = with super; stdenv.mkDerivation rec {
  name = "sift-${version}";
  version = "1.0";

  src = fetchFromGitHub {
    owner = "jwiegley";
    repo = "sift";
    rev = "c823f340be8818cc7aa970f9da4c81247f5b5535";
    sha256 = "1yadjgjcghi2fhyayl3ry67w3cz6f7w0ibni9dikdp3vnxp94y58";
    # date = 2011-09-10T19:05:37-05:00;
  };

  phases = [ "unpackPhase" "installPhase" ];

  installPhase = ''
    mkdir -p $out/bin
    cp -p sift $out/bin
  '';

  meta = {
    homepage = https://github.com/jwiegley/sift;
    description = "A tool for sifting apart large patch files";
    license = lib.licenses.mit;
    maintainers = with lib.maintainers; [ jwiegley ];
  };
};

}
