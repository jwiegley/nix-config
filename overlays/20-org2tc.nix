self: super: {

org2tc = with super; stdenv.mkDerivation rec {
  name = "org2tc-${version}";
  version = "7d52a20";

  src = fetchFromGitHub {
    owner = "jwiegley";
    repo = "org2tc";
    rev = "eb378db6ad9e5ed9f7f4b80ab04b0489574a47bd";
    sha256 = "0mbdz4x1f8zpfhwkqnrxvvqk70h6d7yn314cizxkb7a0qy27zprz";
    # date = 2018-01-26T00:15:37-08:00;
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
