{ pkgs, coq }: with pkgs;

stdenv.mkDerivation rec {
  name = "coq-fiat-core-${coq.coq-version}-unstable-${version}";
  version = "2018-05-14";

  src = pkgs.fetchFromGitHub {
    owner = "jwiegley";
    repo = "fiat-core";
    rev = "5d2d1fdfba7c3ed5a3120dad2415b0bb958b6d02";
    sha256 = "190v5sz8fmdhbndknq9mkwpj3jf570gzdibww7f76g81a34v3qli";
    fetchSubmodules = true;
    # date = 2018-05-14T10:05:32-07:00;
  };

  buildInputs = [ coq coq.ocaml coq.camlp5 coq.findlib
                  pkgs.git pkgs.python3 ];
  propagatedBuildInputs = [ coq ];

  doCheck = false;

  enableParallelBuilding = true;
  buildPhase = "make -j$NIX_BUILD_CORES";

  installPhase = ''
    COQLIB=$out/lib/coq/${coq.coq-version}/
    mkdir -p $COQLIB/user-contrib/Fiat
    cp -pR src/* $COQLIB/user-contrib/Fiat
  '';

  meta = with pkgs.lib; {
    homepage = http://plv.csail.mit.edu/fiat/;
    description = "A library for the Coq proof assistant for synthesizing efficient correct-by-construction programs from declarative specifications";
    maintainers = with maintainers; [ jwiegley ];
    platforms = coq.meta.platforms;
  };

  passthru = {
    compatibleCoqVersions = v: builtins.elem v [ "8.5" "8.6" "8.7" "8.8" ];
  };
}
