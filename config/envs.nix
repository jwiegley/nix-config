self: pkgs:

let myEmacsPackages = import ./emacs.nix pkgs; in rec {
  emacs28Env        = pkgs.emacs28Env        myEmacsPackages;
  emacs28MacPortEnv = pkgs.emacs28MacPortEnv myEmacsPackages;
  emacs29Env        = pkgs.emacs29Env        myEmacsPackages;
  emacsERCEnv       = pkgs.emacsERCEnv       myEmacsPackages;

  inherit (pkgs) ledgerPy3Env;
}
