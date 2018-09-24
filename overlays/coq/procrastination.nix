{ pkgs, coq }: with pkgs;

stdenv.mkDerivation rec {
  name = "coq${coq.coq-version}-procrastination-${version}";
  version = "1.0";

  src = fetchFromGitHub {
    owner = "Armael";
    repo = "coq-procrastination";
    rev = "0f0096313f2ac5dfe8c6852c83dadab25124eca6";
    sha256 = "15mfj8rf85nxg3l5wm1v1p45hysjn0fjny0mi1qi7crxlpp88k0f";
    # date = 2018-09-18T11:17:22+02:00;
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
