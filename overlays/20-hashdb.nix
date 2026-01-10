_: super: {

hashdb = with super; stdenv.mkDerivation rec {
  name = "hashdb-${version}";
  version = "86c8675d";

  src = fetchFromGitHub {
    owner = "jwiegley";
    repo = "hashdb";
    rev = "86c8675d4116c03e81a7468cc66c4c987f1d203e";
    sha256 = "sha256-rs0eqy8yA2YXZd1y6djGIG/WFwvWlSfz08m5qlkG524=";
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
