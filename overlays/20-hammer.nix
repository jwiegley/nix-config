self: super: {

hammer = with super; stdenv.mkDerivation rec {
  name = "hammer-${version}";
  version = "b5a7543b";

  src = fetchFromGitHub {
    owner = "jwiegley";
    repo = "hammer";
    rev = "b5a7543b4741d9b54dad49ecfca8908a4aedf124";
    sha256 = "sha256-SGHB8UTJ9cT/hZiv4V/rc3GwKlB6r9WCYsMXFA+Iw4c=";
    # date = 2011-09-10T19:08:08-05:00;
  };

  phases = [ "unpackPhase" "installPhase" ];

  installPhase = ''
    mkdir -p $out/bin
    cp -p hammer $out/bin
  '';

  meta = {
    homepage = https://github.com/jwiegley/hammer;
    description = "A tool for fixing broken symlinks";
    license = lib.licenses.mit;
    maintainers = with lib.maintainers; [ jwiegley ];
  };
};

}
