self: super: {

tsvutils = with super; stdenv.mkDerivation rec {
  name = "tsvutils-${version}";
  version = "a76c92";

  src = fetchFromGitHub {
    owner = "brendano";
    repo = "tsvutils";
    rev = "777611af8ec27ad2ccbccc007befe6e8947aa5b8";
    sha256 = "0x5s7wbc7cl7c08hlga3hjq7gbmcbdigm58d1bldkwrn8sdx5x0k";
    # date = 2017-02-20T12:35:04-05:00;
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
