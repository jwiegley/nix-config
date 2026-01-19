# overlays/10-coq.nix
# Purpose: Coq theorem prover with IDE disabled (uses Emacs instead)
# Dependencies: Uses final for coqPackages cross-references
# Packages: coq, coq_8_10-coq_9_1, coqPackages, coqPackages_8_10-coqPackages_9_1
final: prev:

{

  coqPackages = final.coqPackages_8_19;

  # coqPackages_HEAD = final.mkCoqPackages final.coq_HEAD;
  coqPackages_9_1 = final.mkCoqPackages final.coq_9_1;
  coqPackages_9_0 = final.mkCoqPackages final.coq_9_0;
  coqPackages_8_20 = final.mkCoqPackages final.coq_8_20;
  coqPackages_8_19 = final.mkCoqPackages final.coq_8_19;
  coqPackages_8_18 = final.mkCoqPackages final.coq_8_18;
  coqPackages_8_17 = final.mkCoqPackages final.coq_8_17;
  coqPackages_8_16 = final.mkCoqPackages final.coq_8_16;
  coqPackages_8_15 = final.mkCoqPackages final.coq_8_15;
  coqPackages_8_14 = final.mkCoqPackages final.coq_8_14;
  coqPackages_8_13 = final.mkCoqPackages final.coq_8_13;
  coqPackages_8_12 = final.mkCoqPackages final.coq_8_12;
  coqPackages_8_11 = final.mkCoqPackages final.coq_8_11;
  coqPackages_8_10 = final.mkCoqPackages final.coq_8_10;

  coq = final.coq_8_19;

  # coq_HEAD = (final.coq_8_19.override {
  #     buildIde = false;
  #     version = /Users/johnw/src/coq;
  #   }).overrideAttrs (attrs: {
  #     buildInputs = attrs.buildInputs
  #       ++ (with prev; [
  #         texlive.combined.scheme-full which hevea fig2dev imagemagick_light git
  #       ]);
  #   });

  coq_9_1 = prev.coq_9_1.override { buildIde = false; };
  coq_9_0 = prev.coq_9_0.override { buildIde = false; };
  coq_8_20 = prev.coq_8_20.override { buildIde = false; };
  coq_8_19 = prev.coq_8_19.override { buildIde = false; };
  coq_8_18 = prev.coq_8_18.override { buildIde = false; };
  coq_8_17 = prev.coq_8_17.override { buildIde = false; };
  coq_8_16 = prev.coq_8_16.override { buildIde = false; };
  coq_8_15 = prev.coq_8_15.override { buildIde = false; };
  coq_8_14 = prev.coq_8_14.override { buildIde = false; };
  coq_8_13 = prev.coq_8_13.override { buildIde = false; };
  coq_8_12 = prev.coq_8_12.override { buildIde = false; };
  coq_8_11 = prev.coq_8_11.override { buildIde = false; };
  coq_8_10 = prev.coq_8_10.override { buildIde = false; };

}
