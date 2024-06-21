self: pkgs:

let myEmacsPackages = import ./emacs.nix pkgs; in rec {
  emacs29MacPortEnv = pkgs.emacs29MacPortEnv myEmacsPackages;
  emacs29Env        = pkgs.emacs29Env        myEmacsPackages;

  inherit (pkgs) ledgerPy3Env;
}
