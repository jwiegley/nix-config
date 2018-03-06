pkgs: version: cpkgs: with pkgs;
[
  ocamlPackages.ocaml
  ocamlPackages.camlp5_transitional
  ocamlPackages.findlib
  ocamlPackages.menhir
  coq2html
  compcert
] ++ (with cpkgs; ([
] ++ (pkgs.stdenv.lib.optionals (version == "8.8+alpha") [
  equations
  # fiat_HEAD
]) ++ (pkgs.stdenv.lib.optionals (version == "8.7") [
  QuickChick
  autosubst
  bignums
  coq-ext-lib
  coq-haskell
  coquelicot
  dpdgraph
  flocq
  heq
  interval
  mathcomp

  CoLoR
  category-theory
  equations
  fiat_HEAD
  math-classes
  metalib
]) ++ (pkgs.stdenv.lib.optionals (version == "8.6") [
  category-theory
  equations
  ssreflect
])))
