{ pkgs, coq, equations }: with pkgs;

stdenv.mkDerivation rec {
  name = "coq${coq.coq-version}-category-theory-${version}";
  version = "1.0";

  src = fetchFromGitHub {
    owner = "jwiegley";
    repo = "category-theory";
    rev = "cfe8882136d8298e10bc00234ee2527ba66f85b3";
    sha256 = "0ml9jn0hzl4kzzk7mgqwmdmxdncn1aqn86lhi29m0dsh4awsllvn";
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
