{ pkgs, coq, equations }: with pkgs;

stdenv.mkDerivation rec {
  name = "coq${coq.coq-version}-category-theory-${version}";
  version = "1.0";

  src = fetchFromGitHub {
    owner = "jwiegley";
    repo = "category-theory";
    rev = "3b9ba7b26a64d49a55e8b6ccea570a7f32c11ead";
    sha256 = "0f2nr8dgn1ab7hr7jrdmr1zla9g9h8216q4yf4wnff9qkln8sbbs";
    # date = 2018-03-26T17:10:21-07:00;
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
