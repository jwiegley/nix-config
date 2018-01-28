self: super: {

hammer = with super; stdenv.mkDerivation rec {
  name = "hammer-${version}";
  version = "1.3";

  src = fetchFromGitHub {
    owner = "jwiegley";
    repo = "hammer";
    rev = "80d3b1270f9912a2f5df7d6078f50aa4d0ed12e4";
    sha256 = "16njr6w6gql5n35cwxdw4mq9g4gjlcc8ca73zkmym3pb0nwvkij7";
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
