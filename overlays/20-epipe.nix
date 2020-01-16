self: super: {

epipe = with super; stdenv.mkDerivation rec {
  name = "epipe-${version}";
  version = "e881004d";

  src = fetchFromGitHub {
    owner = "cute-jumper";
    repo = "epipe";
    rev = "e881004d7d6248fc6a6ea4c197f0bc56acb60583";
    sha256 = "0wa50x5z082vfymiv7zw2azy3kwk1ljnwzrcyf8hjm8jz7b1jm4z";
    # date = 2018-02-16T00:01:43-05:00;
  };

  phases = [ "unpackPhase" "installPhase" ];

  installPhase = ''
    mkdir -p $out/bin
    cp -p epipe $out/bin
  '';

  meta = with stdenv.lib; {
    description = "A fork of vipe to support emacsclient";
    homepage = https://github.com/cute-jumper/epipe;
    license = licenses.mit;
    maintainers = with maintainers; [ jwiegley ];
    platforms = platforms.unix;
  };
};

}
