{ pkgs, coq }: with pkgs;

stdenv.mkDerivation rec {
  name = "coq${coq.coq-version}-equations-${version}";
  version = "8.8+alpha";

  src = fetchFromGitHub {
    owner = "mattam82";
    repo = "Coq-Equations";
    rev = "5f358fb4ff463a7502adf6862efa611dff41350d";
    sha256 = "1iffarnch6grdb7d8ifzlxm45fpmnk5bax9gf556ny5qrnyx8s13";
  };

  buildInputs = [ coq.ocaml coq.camlp5 coq.findlib coq ];

  preBuild = "coq_makefile -f _CoqProject -o Makefile";

  installFlags = "COQLIB=$(out)/lib/coq/${coq.coq-version}/";

  meta = with stdenv.lib; {
    homepage = https://mattam82.github.io/Coq-Equations/;
    description = "A plugin for Coq to add dependent pattern-matching";
    maintainers = with maintainers; [ jwiegley ];
    platforms = coq.meta.platforms;
  };

  passthru = {
    compatibleCoqVersions = v: builtins.elem v [ "8.8+alpha" ];
  };
}
