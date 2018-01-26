self: super: {

org2tc = with super; stdenv.mkDerivation rec {
  name = "org2tc-${version}";
  version = "7d52a20";

  src = fetchFromGitHub {
    owner = "jwiegley";
    repo = "org2tc";
    rev = "7d52a20a8957264cbca0f1678f2f3d14155ac3f6";
    sha256 = "1173ljh94sr2wfy9qfbk8rapsn8j708hc9mgwy10gz721mqhpjxj";
    # date = 2018-01-25T23:39:06-08:00;
  };

  phases = [ "unpackPhase" "installPhase" ];

  installPhase = ''
    mkdir -p $out/bin
    cp -p org2tc $out/bin
  '';

  meta = with stdenv.lib; {
    description = "Conversion utility from Org-mode to timeclock format";
    homepage = https://github.com/jwiegley/org2tc;
    license = licenses.mit;
    maintainers = with maintainers; [ jwiegley ];
    platforms = platforms.unix;
  };
};

}
