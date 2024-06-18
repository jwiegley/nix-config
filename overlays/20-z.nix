self: super: {

z = with super; stdenv.mkDerivation rec {
  name = "z-${version}";
  version = "d37a763a";

  src = fetchFromGitHub {
    owner = "rupa";
    repo = "z";
    rev = "d37a763a6a30e1b32766fecc3b8ffd6127f8a0fd";
    sha256 = "10azqw3da1mamfxhx6r0x481gsnjjipcfv6q91vp2bhsi22l35hy";
    # date = 2023-12-09T17:41:33-05:00;
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
