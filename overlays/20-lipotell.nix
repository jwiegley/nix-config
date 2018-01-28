self: super: {

lipotell = with super; stdenv.mkDerivation rec {
  name = "lipotell-${version}";
  version = "1.1";

  src = fetchFromGitHub {
    owner = "jwiegley";
    repo = "lipotell";
    rev = "1502a4753f42618efcf2d0d561c818af377b0d92";
    sha256 = "0vnkbf0ldzh2b7aiwhpxl5dr1h158xnbw2i8q4hwxkfialca4xjf";
    # date = 2011-09-10T18:57:01-05:00;
  };

  phases = [ "unpackPhase" "installPhase" ];

  installPhase = ''
    mkdir -p $out/bin
    cp -p lipotell $out/bin
  '';

  meta = {
    homepage = https://github.com/jwiegley/lipotell;
    description = "A tool to find large files within a directory";
    license = lib.licenses.mit;
    maintainers = with lib.maintainers; [ jwiegley ];
  };
};

}
