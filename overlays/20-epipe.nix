self: super: {

epipe = with super; stdenv.mkDerivation rec {
  name = "epipe-${version}";
  version = "a76c92";

  src = fetchFromGitHub {
    owner = "cute-jumper";
    repo = "epipe";
    rev = "a76c922ef9909f4a166e0568ec0e6aa59cd89de2";
    sha256 = "0wbqbvkhlf84ihq8iznh224pjcm59clvbxcgrjvp8scdwqc6idh7";
    # date = 2016-10-25T04:02:26-04:00;
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
