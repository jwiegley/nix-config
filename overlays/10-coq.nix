# overlays/10-coq.nix
# Purpose: Coq theorem prover with IDE disabled (uses Emacs instead)
# Dependencies: Uses final for coqPackages cross-references
# Packages: default and versioned coq/coqPackages aliases
final: prev:

{

  coqPackages = final.coqPackages_9_1;

  coqPackages_9_1 = final.mkCoqPackages final.coq_9_1;
  coqPackages_9_0 = final.mkCoqPackages final.coq_9_0;
  coqPackages_8_20 = final.mkCoqPackages final.coq_8_20;
  coqPackages_8_19 = final.mkCoqPackages final.coq_8_19;

  coq = final.coq_9_1;

  coq_9_1 = prev.coq_9_1.override { buildIde = false; };
  coq_9_0 = prev.coq_9_0.override { buildIde = false; };
  coq_8_20 = prev.coq_8_20.override { buildIde = false; };
  coq_8_19 = prev.coq_8_19.override { buildIde = false; };

}
