self: super: {

z = with super; stdenv.mkDerivation rec {
  name = "z-${version}";
  version = "4f08e7fe";

  src = fetchFromGitHub {
    owner = "rupa";
    repo = "z";
    rev = "4f08e7febba8d024cbf583544a8cd563e02c3413";
    sha256 = "0rx75149wnxmbgys0ayyq61rfv4h19j3d1kh27hqa11k5gf2p0lp";
    # date = 2019-10-24T01:49:52-04:00;
  };

  phases = [ "unpackPhase" "installPhase" ];

  installPhase = ''
    mkdir -p $out/share
    cp -p z.sh $out/share/z.sh
  '';

  meta = with stdenv.lib; {
    description = "Tracks your most used directories, based on 'frecency'.";
    homepage = https://github.com/rupa/z;
    license = licenses.mit;
    maintainers = with maintainers; [ jwiegley ];
    platforms = platforms.unix;
  };
};

}
