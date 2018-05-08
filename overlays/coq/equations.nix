{ pkgs, coq }: with pkgs;

stdenv.mkDerivation rec {
  name = "coq${coq.coq-version}-equations-${version}";
  version = "1.0";

  src = fetchFromGitHub {
    owner = "mattam82";
    repo = "Coq-Equations";
    rev = "v1.0-8.8";
    sha256 = "0dd7zd5j2sv5cw3mfwg33ss2vcj634q3qykakc41sv7f3rfgqfnn";
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
    compatibleCoqVersions = v: builtins.elem v [ "8.8" ];
  };
}
