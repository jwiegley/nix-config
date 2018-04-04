pkgs: version: cpkgs: with pkgs;
[
  ocamlPackages.ocaml
  ocamlPackages.camlp5_transitional
  ocamlPackages.findlib
  ocamlPackages.menhir
  coq2html
] ++ (with cpkgs; ([
] ++ (pkgs.stdenv.lib.optionals (version == "8.8+beta1") [
  equations
]) ++ (pkgs.stdenv.lib.optionals (version == "8.7") [
  QuickChick
  autosubst
  bignums
  compcert
  coq-ext-lib
  coq-haskell
  coquelicot
  dpdgraph
  flocq
  heq
  interval
  mathcomp
  coq-haskell
  category-theory

  CoLoR
  equations
  fiat_HEAD
  math-classes
  metalib
]) ++ (pkgs.stdenv.lib.optionals (version == "8.6") [
  equations
  ssreflect
  coq-haskell
])))
