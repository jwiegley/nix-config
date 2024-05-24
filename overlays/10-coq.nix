self: pkgs:

{

coqPackages = self.coqPackages_8_19;

# coqPackages_HEAD = self.mkCoqPackages self.coq_HEAD;
coqPackages_8_19 = self.mkCoqPackages self.coq_8_19;
coqPackages_8_18 = self.mkCoqPackages self.coq_8_18;
coqPackages_8_17 = self.mkCoqPackages self.coq_8_17;
coqPackages_8_16 = self.mkCoqPackages self.coq_8_16;
coqPackages_8_15 = self.mkCoqPackages self.coq_8_15;
coqPackages_8_14 = self.mkCoqPackages self.coq_8_14;
coqPackages_8_13 = self.mkCoqPackages self.coq_8_13;
coqPackages_8_12 = self.mkCoqPackages self.coq_8_12;
coqPackages_8_11 = self.mkCoqPackages self.coq_8_11;
coqPackages_8_10 = self.mkCoqPackages self.coq_8_10;

coq = self.coq_8_19;

# coq_HEAD = (self.coq_8_16.override {
#     buildIde = false;
#     version = ~/src/coq;
#   }).overrideAttrs (attrs: {
#     buildInputs = attrs.buildInputs
#       ++ (with pkgs; [
#         texlive.combined.scheme-full which hevea fig2dev imagemagick_light git
#       ]);
#   });

coq_8_19 = pkgs.coq_8_19.override { buildIde = false; };
coq_8_18 = pkgs.coq_8_18.override { buildIde = false; };
coq_8_17 = pkgs.coq_8_17.override { buildIde = false; };
coq_8_16 = pkgs.coq_8_16.override { buildIde = false; };
coq_8_15 = pkgs.coq_8_15.override { buildIde = false; };
coq_8_14 = pkgs.coq_8_14.override { buildIde = false; };
coq_8_13 = pkgs.coq_8_13.override { buildIde = false; };
coq_8_12 = pkgs.coq_8_12.override { buildIde = false; };
coq_8_11 = pkgs.coq_8_11.override { buildIde = false; };
coq_8_10 = pkgs.coq_8_10.override { buildIde = false; };

}
