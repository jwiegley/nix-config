self: pkgs: {

texFull = pkgs.texlive.combine {
  inherit (pkgs.texlive) scheme-full texdoc latex2e-help-texinfo;
  pkgFilter = pkg:
     pkg.tlType == "run"
  || pkg.tlType == "bin"
  || pkg.pname == "latex2e-help-texinfo";
};

}
