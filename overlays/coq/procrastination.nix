{ pkgs, coq }: with pkgs;

stdenv.mkDerivation rec {
  name = "coq${coq.coq-version}-procrastination-${version}";
  version = "1.0";

  src = fetchFromGitHub {
    owner = "Armael";
    repo = "coq-procrastination";
    rev = "199dab4435148e4bdfdf934836c644c2c4e44073";
    sha256 = "0mnm0knzgn0mvq875pfghg3fhwvkr3fpkgwd6brb7hadfxh2xjay";
    # date = 2019-10-14T15:18:05+02:00;
  };

  buildInputs = [ coq.ocaml coq.camlp5 coq.findlib coq ];

  preBuild = "make";

  installFlags = "COQLIB=$(out)/lib/coq/${coq.coq-version}/";

  meta = with stdenv.lib; {
    homepage = https://github.com/Armael/coq-procrastination;
    description = "A small Coq library for collecting side conditions and deferring their proof";
    maintainers = with maintainers; [ jwiegley ];
    platforms = coq.meta.platforms;
  };

  passthru = {
    compatibleCoqVersions = v: builtins.elem v [ "8.5" "8.6" "8.7" "8.8" "8.9" "8.10" ];
  };
}
