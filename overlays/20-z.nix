self: super: {

z = with super; stdenv.mkDerivation rec {
  name = "z-${version}";
  version = "f1f113d9";

  src = fetchFromGitHub {
    owner = "rupa";
    repo = "z";
    rev = "bbec3cb6af844e3f6d95bd7f28435abe0b5d21af";
    sha256 = "1p37hsfwyryq7pdphcd3m8pykzfny80da6q6c9jdxksma3zp4jdq";
    # date = 2020-04-03T01:56:04-04:00;
  };

  phases = [ "unpackPhase" "installPhase" ];

  installPhase = ''
    mkdir -p $out/share
    cp -p z.sh $out/share/z.sh
  '';

  meta = with super.lib; {
    description = "Tracks your most used directories, based on 'frecency'.";
    homepage = https://github.com/rupa/z;
    license = licenses.mit;
    maintainers = with maintainers; [ jwiegley ];
    platforms = platforms.unix;
  };
};

}
