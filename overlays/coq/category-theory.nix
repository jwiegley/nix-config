{ pkgs, coq, equations }: with pkgs;

stdenv.mkDerivation rec {
  name = "coq${coq.coq-version}-category-theory-${version}";
  version = "1.0";

  src = fetchFromGitHub {
    owner = "jwiegley";
    repo = "category-theory";
    rev = "380ff60d34c306f7005babc3dade1d96b5eeb935";
    sha256 = "1r4v5lm090i23kqa1ad39sgfph7pfl458kh8rahsh1mr6yl1cbv9";
    # date = 2020-01-12T15:09:07-08:00;
  };

  # src = builtins.filterSource (path: type:
  #     let baseName = baseNameOf path; in
  #     !( type == "directory" && builtins.elem baseName [".git"])
  #     &&
  #     !( type == "unknown"
  #        || pkgs.stdenv.lib.hasSuffix ".vo" path
  #        || pkgs.stdenv.lib.hasSuffix ".aux" path
  #        || pkgs.stdenv.lib.hasSuffix ".v.d" path
  #        || pkgs.stdenv.lib.hasSuffix ".glob" path))
  #   ~/src/category-theory;

  buildInputs = [ coq.ocaml coq.camlp5 coq.findlib coq equations ];

  preBuild = "coq_makefile -f _CoqProject -o Makefile";

  installFlags = "COQLIB=$(out)/lib/coq/${coq.coq-version}/";

  meta = with stdenv.lib; {
    homepage = https://github.com/jwiegley/category-theory;
    description = "An axiom-free category theory library in Coq";
    maintainers = with maintainers; [ jwiegley ];
    platforms = coq.meta.platforms;
  };

  passthru = {
    compatibleCoqVersions = v: builtins.elem v [ "8.5" "8.6" "8.7" "8.8" ];
  };
}
