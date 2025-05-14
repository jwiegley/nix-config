self: super: {

linkdups = with super; stdenv.mkDerivation rec {
  name = "linkdups-${version}";
  version = "1.3";

  src = fetchFromGitHub {
    owner = "jwiegley";
    repo = "linkdups";
    rev = "57bb79332d3b79418692d0c974acba83a4fd3fc9";
    sha256 = "1d400vanbsrmfxf1w4na3r4k3nw18xnv05qcf4rkqajmnfrbzh3h";
    # date = 2025-05-13T11:29:24-07:00;
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
