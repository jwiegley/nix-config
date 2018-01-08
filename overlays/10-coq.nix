self: pkgs: rec {

myCoqPackages = coqPkgs: with pkgs; [
  ocamlPackages.ocaml
  ocamlPackages.camlp5_transitional
  ocamlPackages.findlib
  ocamlPackages.menhir
  coq2html
  compcert
] ++ (with coqPkgs; [
  QuickChick
  autosubst
  bignums
  coq-ext-lib
  coq-haskell
  # coq-pipes
  coquelicot
  dpdgraph
  flocq
  heq
  interval
  mathcomp
]);

coq_8_7_override = pkgs.coq_8_7.override {
  ocamlPackages = pkgs.ocaml-ng.ocamlPackages_4_06;
  buildIde = false;
};

self: pkgs: rec {

coq_HEAD = pkgs.stdenv.lib.overrideDerivation coq_8_7_override (attrs: rec {
  version = "8.8";
  name = "coq-${version}-pre";
  coq-version = "${version}";
  src = ~/oss/coq;
  buildInputs = attrs.buildInputs
    ++ (with pkgs; [ ocaml-ng.ocamlPackages_4_06.num
                     texFull hevea fig2dev imagemagick_light ]);
  preConfigure = ''
    configureFlagsArray=(
      -with-doc no
      -coqide no
    )
  '';
});

coqPackages_HEAD = pkgs.mkCoqPackages coq_HEAD;

coqHEADEnv = pkgs.myEnvFun {
  name = "coqHEAD";
  buildInputs = [ coq_HEAD ];
};

coq87Env = pkgs.myEnvFun {
  name = "coq87";
  buildInputs = [ pkgs.coq_8_7 ]
    ++ myCoqPackages pkgs.coqPackages_8_7 ++
    (with pkgs.coqPackages_8_7; [
       CoLoR
       category-theory
       equations
       math-classes
       metalib
     ])
    ++ (with pkgs.coqPackages_8_7.contribs; [
      # aac-tactics
      abp
      additions
      ails
      algebra
      # amm11262
      angles
      area-method
      # atbr
      automata
      axiomatic-abp
      # bdds
      bertrand
      buchberger
      canon-bdds
      # cantor
      cats-in-zfc
      ccs
      cfgv
      checker
      chinese
      circuits
      # classical-realizability
      coalgebras
      coinductive-examples
      # coinductive-reals
      concat
      constructive-geometry
      # containers
      # continuations
      coq-in-coq
      coqoban
      # corn
      # counting
      cours-de-coq
      ctltctl
      dblib
      demos
      dep-map
      # descente-infinie
      dictionaries
      distributed-reference-counting
      domain-theory
      # ergo
      euclidean-geometry
      euler-formula
      exact-real-arithmetic
      exceptions
      fairisle
      fermat4
      finger-tree
      firing-squad
      float
      founify
      free-groups
      fsets
      fssec-model
      functions-in-zfc
      fundamental-arithmetics
      gc
      generic-environments
      # goedel
      graph-basics
      # graphs
      group-theory
      groups
      hardware
      hedges
      # high-school-geometry
      higman-cf
      higman-nw
      higman-s
      historical-examples
      hoare-tut
      huffman
      icharate
      idxassoc
      ieee754
      int-map
      # intuitionistic-nuprl
      ipc
      izf
      jordan-curve-theorem
      # jprover
      karatsuba
      kildall
      lambda
      lambek
      lazy-pcf
      lc
      # legacy-field
      # legacy-ring
      # lemma-overloading
      lesniewski-mereology
      # lin-alg
      ltl
      # maple-mode
      markov
      # math-classes
      maths
      matrices
      micromega
      mini-compiler
      minic
      miniml
      mod-red
      multiplier
      mutual-exclusion
      # nfix
      # orb-stab
      otway-rees
      paco
      paradoxes
      param-pi
      pautomata
      persistent-union-find
      pi-calc
      pocklington
      # presburger
      prfx
      projective-geometry
      propcalc
      pts
      ptsatr
      # ptsf
      qarith
      qarith-stern-brocot
      quicksort-complexity
      railroad-crossing
      ramsey
      random
      # rational
      # recursive-definition
      reflexive-first-order
      regexp
      # relation-algebra
      # relation-extraction
      rem
      rsa
      ruler-compass-geometry
      schroeder
      search-trees
      # semantics
      shuffle
      # smc
      square-matrices
      # stalmarck
      streams
      # string
      subst
      sudoku
      sum-of-two-square
      tait
      tarski-geometry
      three-gap
      # topology
      tortoise-hare-algorithm
      traversable-fincontainer
      # tree-automata
      tree-diameter
      weak-up-to
      zchinese
      zf
      zfc
      zorns-lemma
      zsearch-trees
    ]);
};

coq86Env = pkgs.myEnvFun {
  name = "coq86";
  buildInputs = [ pkgs.coq_8_6 ]
    ++ myCoqPackages pkgs.coqPackages_8_6 ++
    (with pkgs.coqPackages_8_6; [
       category-theory
       equations
       ssreflect
     ])
    ++ (with pkgs.coqPackages_8_6.contribs; [
      # aac-tactics
      abp
      additions
      # ails
      algebra
      amm11262
      angles
      area-method
      # atbr
      automata
      axiomatic-abp
      # bdds
      # bertrand
      buchberger
      canon-bdds
      cantor
      cats-in-zfc
      ccs
      cfgv
      checker
      chinese
      circuits
      classical-realizability
      coalgebras
      coinductive-examples
      # coinductive-reals
      concat
      constructive-geometry
      # containers
      # continuations
      coq-in-coq
      coqoban
      # corn
      # counting
      cours-de-coq
      ctltctl
      dblib
      demos
      dep-map
      # descente-infinie
      dictionaries
      distributed-reference-counting
      domain-theory
      # ergo
      euclidean-geometry
      euler-formula
      exact-real-arithmetic
      exceptions
      fairisle
      # fermat4
      finger-tree
      firing-squad
      # float
      founify
      free-groups
      fsets
      fssec-model
      functions-in-zfc
      fundamental-arithmetics
      gc
      generic-environments
      # goedel
      graph-basics
      # graphs
      group-theory
      groups
      hardware
      hedges
      high-school-geometry
      higman-cf
      higman-nw
      higman-s
      historical-examples
      hoare-tut
      huffman
      icharate
      idxassoc
      ieee754
      int-map
      # intuitionistic-nuprl
      ipc
      izf
      jordan-curve-theorem
      # jprover
      karatsuba
      kildall
      lambda
      lambek
      lazy-pcf
      lc
      # legacy-field
      # legacy-ring
      # lemma-overloading
      lesniewski-mereology
      # lin-alg
      ltl
      # maple-mode
      # markov
      math-classes
      maths
      matrices
      micromega
      mini-compiler
      minic
      miniml
      mod-red
      multiplier
      mutual-exclusion
      # nfix
      # orb-stab
      otway-rees
      paco
      paradoxes
      param-pi
      pautomata
      persistent-union-find
      pi-calc
      pocklington
      # presburger
      prfx
      projective-geometry
      propcalc
      pts
      ptsatr
      # ptsf
      qarith
      # qarith-stern-brocot
      quicksort-complexity
      railroad-crossing
      ramsey
      random
      # rational
      # recursive-definition
      reflexive-first-order
      regexp
      # relation-algebra
      # relation-extraction
      rem
      rsa
      ruler-compass-geometry
      schroeder
      search-trees
      # semantics
      shuffle
      # smc
      square-matrices
      # stalmarck
      streams
      # string
      subst
      sudoku
      sum-of-two-square
      tait
      tarski-geometry
      three-gap
      # topology
      tortoise-hare-algorithm
      # traversable-fincontainer
      # tree-automata
      tree-diameter
      weak-up-to
      zchinese
      zf
      zfc
      zorns-lemma
      zsearch-trees
    ]);
};

coq85Env = pkgs.myEnvFun {
  name = "coq85";
  buildInputs = [ pkgs.coq_8_5 ]
    ++ myCoqPackages pkgs.coqPackages_8_5
    ++ (with pkgs.coqPackages_8_5.contribs; [
      # aac-tactics
      abp
      # additions
      # ails
      algebra
      amm11262
      angles
      area-method
      # atbr
      automata
      axiomatic-abp
      # bdds
      # bertrand
      # buchberger
      # canon-bdds
      cantor
      cats-in-zfc
      ccs
      cfgv
      checker
      # chinese
      circuits
      # classical-realizability
      coalgebras
      coinductive-examples
      # coinductive-reals
      concat
      constructive-geometry
      # containers
      # continuations
      # coq-in-coq
      coqoban
      # corn
      # counting
      cours-de-coq
      ctltctl
      dblib
      demos
      dep-map
      # descente-infinie
      dictionaries
      distributed-reference-counting
      domain-theory
      # ergo
      # euclidean-geometry
      euler-formula
      exact-real-arithmetic
      # exceptions
      fairisle
      # fermat4
      finger-tree
      # firing-squad
      # float
      # founify
      free-groups
      # fsets
      fssec-model
      functions-in-zfc
      fundamental-arithmetics
      gc
      generic-environments
      # goedel
      graph-basics
      # graphs
      group-theory
      groups
      # hardware
      hedges
      # high-school-geometry
      # higman-cf
      # higman-nw
      higman-s
      historical-examples
      hoare-tut
      # huffman
      icharate
      idxassoc
      # ieee754
      int-map
      # intuitionistic-nuprl
      # ipc
      izf
      jordan-curve-theorem
      # jprover
      karatsuba
      kildall
      lambda
      lambek
      lazy-pcf
      lc
      # legacy-field
      # legacy-ring
      # lemma-overloading
      lesniewski-mereology
      # lin-alg
      ltl
      # maple-mode
      # markov
      # math-classes
      maths
      matrices
      micromega
      mini-compiler
      # minic
      miniml
      mod-red
      # multiplier
      # mutual-exclusion
      # nfix
      # orb-stab
      otway-rees
      paco
      # paradoxes
      param-pi
      # pautomata
      persistent-union-find
      pi-calc
      pocklington
      # presburger
      prfx
      # projective-geometry
      propcalc
      # pts
      ptsatr
      # ptsf
      # qarith
      # qarith-stern-brocot
      # quicksort-complexity
      railroad-crossing
      ramsey
      random
      # rational
      # recursive-definition
      reflexive-first-order
      regexp
      # relation-algebra
      # relation-extraction
      rem
      rsa
      # ruler-compass-geometry
      schroeder
      # search-trees
      # semantics
      shuffle
      # smc
      # square-matrices
      # stalmarck
      streams
      # string
      subst
      # sudoku
      sum-of-two-square
      # tait
      tarski-geometry
      three-gap
      # topology
      tortoise-hare-algorithm
      # traversable-fincontainer
      # tree-automata
      tree-diameter
      weak-up-to
      # zchinese
      zf
      zfc
      zorns-lemma
      # zsearch-trees
    ]);
};

coqPackages_8_4 = pkgs.mkCoqPackages pkgs.coq_8_4;

coq84Env = pkgs.myEnvFun {
  name = "coq84";
  buildInputs = [ pkgs.coq_8_4 ];
};

}
