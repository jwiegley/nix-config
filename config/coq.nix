pkgs: version: cpkgs: with pkgs;
[
  ocamlPackages.ocaml
  ocamlPackages.camlp5_transitional
  ocamlPackages.findlib
  ocamlPackages.menhir
  coq2html
  compcert
] ++ (with cpkgs; [
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
]) ++ (pkgs.stdenv.lib.optionals (version == "8.7") [
  CoLoR
  category-theory
  equations
  math-classes
  metalib
]) ++ (pkgs.stdenv.lib.optionals (version == "8.6") [
  category-theory
  equations
  ssreflect
])
