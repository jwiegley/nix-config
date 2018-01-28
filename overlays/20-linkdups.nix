self: super: {

linkdups = with super; stdenv.mkDerivation rec {
  name = "linkdups-${version}";
  version = "1.2";

  src = fetchFromGitHub {
    owner = "jwiegley";
    repo = "linkdups";
    rev = "d822bf05163581fabfc60e32ec820b5f67f5d6db";
    sha256 = "07cw7ymz1kpwf8m3wgj868bj6qc9yjv886g53wa9gv84v77v8hk7";
    # date = 2018-01-27T17:08:24-08:00;
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
