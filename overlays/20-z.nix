self: super: {

bash-z = with super; stdenv.mkDerivation rec {
  name = "z-${version}";
  version = "2ebe41";

  src = fetchFromGitHub {
    owner = "rupa";
    repo = "z";
    rev = "2ebe419ae18316c5597dd5fb84b5d8595ff1dde9";
    sha256 = "18ajkfdnyzww75mgkydfjgh4fl34fsw081s2hyvjbab8q9l69f6h";
  };

  phases = [ "unpackPhase" "installPhase" ];

  installPhase = ''
    mkdir -p $out/bin
    cp -p z.sh $out/share/bash/z.sh
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
