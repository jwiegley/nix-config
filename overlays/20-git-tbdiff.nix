self: super: {

git-tbdiff = with super; stdenv.mkDerivation rec {
  name = "git-tbdiff-${version}";
  version = "047d1c";

  src = fetchFromGitHub {
    owner = "trast";
    repo = "tbdiff";
    rev = "047d1c79dfada57522a42f307cd4b0ddcb098934";
    sha256 = "1r4fyjc0xzdiyg6xcslf9afqla83cxsfrpmi3c1qzq8s2gsac7bj";
    # date = 2013-07-22T12:19:19+02:00;
  };

  phases = [ "unpackPhase" "buildPhase" "installPhase" ];

  buildPhase = ''
    sed -i -e 's|/usr/bin/python2|${pkgs.python27}/bin/python|' git-tbdiff.py
  '';

  installPhase = ''
    mkdir -p $out/bin
    cp -p git-tbdiff.py $out/bin/git-tbdiff
  '';

  meta = with super.lib; {
    description = "tbdiff shows the differences between two versions of a patch series";
    homepage = https://github.com/trast/tbdiff;
    license = licenses.mit;
    maintainers = with maintainers; [ jwiegley ];
    platforms = platforms.unix;
  };
};

}
