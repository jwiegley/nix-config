self: super: {

tsvutils = with super; stdenv.mkDerivation rec {
  name = "tsvutils-${version}";
  version = "a286c817";

  src = fetchFromGitHub {
    owner = "brendano";
    repo = "tsvutils";
    rev = "a286c8179342285803871834bb92c39cd52e516d";
    sha256 = "1jrg36ckvpmwjx9350lizfjghr3pfrmad0p3qibxwj14qw3wplni";
    # date = 2019-08-11T16:06:16-04:00;
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
