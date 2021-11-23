self: pkgs:

let myEmacsPackages = import ./emacs.nix pkgs; in rec {
  emacs27Env  = pkgs.emacs27Env  myEmacsPackages;
  emacsERCEnv = pkgs.emacsERCEnv myEmacsPackages;

  inherit (pkgs) ledgerPy2Env ledgerPy3Env;

  projects-env = pkgs.stdenv.mkDerivation rec {
    name = "projects";
    srcs = [
    ];
    phases = ["buildPhase" "installPhase"];
    buildPhase = "true";
    installPhase = ''
      mkdir $out
    '' + (pkgs.lib.concatStrings (builtins.map (src: ''
      ln -s ${src} $out
    '') srcs));
  };
}
