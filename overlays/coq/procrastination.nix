{ pkgs, coq }: with pkgs;

stdenv.mkDerivation rec {
  name = "coq${coq.coq-version}-procrastination-${version}";
  version = "1.0";

  src = fetchFromGitHub {
    owner = "Armael";
    repo = "coq-procrastination";
    rev = "2472ef79b7f84169344a42dd94dc5fdea6869c98";
    sha256 = "0fqhc1x80v7bsvfmmh40abym1036qbipp9zh53bgczd232ipallc";
    # date = 2018-09-21T14:54:50+02:00;
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
    compatibleCoqVersions = v: builtins.elem v [ "8.5" "8.6" "8.7" "8.8" ];
  };
}
