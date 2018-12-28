self: super: {

tsvutils = with super; stdenv.mkDerivation rec {
  name = "tsvutils-${version}";
  version = "d252d7";

  src = fetchFromGitHub {
    owner = "brendano";
    repo = "tsvutils";
    rev = "d252d7664d43f9246629cc6df65cf2452a96479e";
    sha256 = "17y339grdywqcgifzjr18qh74pgx8dan1zmgkcbvvyii38l3kv8f";
    # date = 2018-05-16T15:28:17-04:00;
  };

  phases = [ "unpackPhase" "installPhase" ];

  installPhase = ''
    mkdir -p $out/bin
    find . -maxdepth 1 \( -type f -o -type l \) -executable \
        -exec cp -pL {} $out/bin \;
  '';

  meta = with stdenv.lib; {
    description = "Utilities for processing tab-separated files";
    homepage = https://github.com/brendano/tsvutils;
    license = licenses.mit;
    maintainers = with maintainers; [ jwiegley ];
    platforms = platforms.unix;
  };
};

}
