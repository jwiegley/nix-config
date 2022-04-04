self: pkgs:

{

coq_HEAD = with pkgs; pkgs.lib.overrideDerivation self.coq_8_15 (attrs: rec {
  version = "dev";
  name = "coq-${version}";
  coq-version = version;
  buildIde = false;
  src = ~/src/coq;
  propagatedBuildInputs = [
     pkgs.ocamlPackages.zarith
  ];
  buildInputs = attrs.buildInputs
    ++ (with pkgs; [
      texlive.combined.scheme-full which hevea fig2dev imagemagick_light git
    ]);
});

coqPackages = self.coqPackages_8_15;

coqPackages_HEAD = self.mkCoqPackages self.coq_HEAD;
coqPackages_8_15 = self.mkCoqPackages self.coq_8_15;
coqPackages_8_14 = self.mkCoqPackages self.coq_8_14;
coqPackages_8_13 = self.mkCoqPackages self.coq_8_13;
coqPackages_8_12 = self.mkCoqPackages self.coq_8_12;
coqPackages_8_11 = self.mkCoqPackages self.coq_8_11;
coqPackages_8_10 = self.mkCoqPackages self.coq_8_10;
coqPackages_8_9  = self.mkCoqPackages self.coq_8_9;
coqPackages_8_8  = self.mkCoqPackages self.coq_8_8;
coqPackages_8_7  = self.mkCoqPackages self.coq_8_7;
coqPackages_8_6  = self.mkCoqPackages self.coq_8_6;

coq_8_15 = pkgs.coq_8_15.override { buildIde = false; };
coq_8_14 = pkgs.coq_8_14.override { buildIde = false; };
coq_8_13 = pkgs.coq_8_13.override { buildIde = false; };
coq_8_12 = pkgs.coq_8_12.override { buildIde = false; };
coq_8_11 = pkgs.coq_8_11.override { buildIde = false; };
coq_8_10 = pkgs.coq_8_10.override { buildIde = false; };

}
