{ pkgs, coq }: with pkgs;

stdenv.mkDerivation rec {
  name = "coq${coq.coq-version}-equations-${version}";
  version = "8.8+alpha";

  src = fetchFromGitHub {
    owner = "mattam82";
    repo = "Coq-Equations";
    rev = "c0c7e993bc1a745bed70065bdb5e94948a63f402";
    sha256 = "10qmfbzm21dgnh42y8wp5wkjw8wvfydnzcw4r7vh448avgcr18jw";
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
