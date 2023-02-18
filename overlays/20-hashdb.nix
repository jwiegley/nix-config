_: super: {

hashdb = with super; stdenv.mkDerivation rec {
  name = "hashdb-${version}";
  version = "1.0";

  src = fetchFromGitHub {
    owner = "jwiegley";
    repo = "hashdb";
    rev = "86c8675d4116c03e81a7468cc66c4c987f1d203e";
    sha256 = "0vp70rcsmff9sgrjg5fn1cbxcvr0qvcfjwnxclbnc0rj5ymixkdf";
    # date = 2011-10-04T03:27:40-05:00;
  };

  phases = [ "unpackPhase" "installPhase" ];

  installPhase = ''
    mkdir -p $out/bin
    cp -p hashdb $out/bin
  '';

  meta = {
    homepage = https://github.com/jwiegley/hashdb;
    description = "A simply key/value store for keeping hashes";
    license = lib.licenses.mit;
    maintainers = with lib.maintainers; [ jwiegley ];
  };
};

}
