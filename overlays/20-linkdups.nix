self: super: {

linkdups = with super; stdenv.mkDerivation rec {
  name = "linkdups-${version}";
  version = "1.2";

  src = fetchFromGitHub {
    owner = "jwiegley";
    repo = "linkdups";
    rev = "7eb8be7a177b81f6fd9a0604f3062871247dc51f";
    sha256 = "059kadjar52ms1fan0s076a60jrki9vj93xw6nyv4iw2bf27y6k6";
    # date = 2025-04-11T09:08:02+02:00;
  };

  phases = [ "unpackPhase" "installPhase" ];

  installPhase = ''
    mkdir -p $out/bin
    cp -p linkdups $out/bin
  '';

  meta = {
    homepage = https://github.com/jwiegley/linkdups;
    description = "A tool for hard-linking duplicate files";
    license = lib.licenses.mit;
    maintainers = with lib.maintainers; [ jwiegley ];
  };
};

}
