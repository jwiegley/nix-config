self: super: {

z = with super; stdenv.mkDerivation rec {
  name = "z-${version}";
  version = "f1f113d9";

  src = fetchFromGitHub {
    owner = "rupa";
    repo = "z";
    rev = "f1f113d9bae9effaef6b1e15853b5eeb445e0712";
    sha256 = "1d0wwdjb0sgxzszbi7jnsnc6887h026r6hn4kzv9hjp1axr0dxrx";
    # date = 2020-02-15T16:56:40-05:00;
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
