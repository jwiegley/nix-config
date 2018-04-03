{ pkgs, coq, ssreflect }: with pkgs;

stdenv.mkDerivation rec {
  name = "coq${coq.coq-version}-haskell-${version}";
  version = "1.0";

  src = ~/src/coq-haskell;

  buildInputs = [ coq.ocaml coq.camlp5 coq.findlib coq ssreflect ];

  preBuild = "coq_makefile -f _CoqProject -o Makefile";

  installFlags = "COQLIB=$(out)/lib/coq/${coq.coq-version}/";

  meta = with stdenv.lib; {
    homepage = https://github.com/jwiegley/coq-haskell;
    description = "A library for Haskell users writing Coq programs";
    maintainers = with maintainers; [ jwiegley ];
    platforms = coq.meta.platforms;
  };

  passthru = {
    compatibleCoqVersions = v: builtins.elem v [ "8.5" "8.6" "8.7" "8.8+alpha" ];
  };
}
