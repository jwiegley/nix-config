self: super: {

imgcat = with super; stdenv.mkDerivation rec {
  name = "imgcat-${version}";
  version = "2.2.0";

  src = fetchFromGitHub {
    owner = "eddieantonio";
    repo = "imgcat";
    rev = "137f5cbfb3b48585651539c289d958ca3c4f9952";
    sha256 = "0298v012i4a18p4jh3d8724zqg349m0wfs45wa5x0jpbrx4hxrzh";
    # date = 2018-05-05T15:35:20-06:00;
  };

  meta = with stdenv.lib; {
    description = "It's like cat, but for images";
    homepage = https://github.com/eddieantonio/imgcat;
    license = licenses.mit;
    maintainers = with maintainers; [ jwiegley ];
    platforms = platforms.unix;
  };
};

}
