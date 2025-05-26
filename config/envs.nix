self: pkgs:

let myEmacsPackages = import ./emacs.nix pkgs; in rec {
  emacs29MacPortEnv = pkgs.emacs29MacPortEnv myEmacsPackages;
  emacs30Env = pkgs.emacs30Env myEmacsPackages;
  emacsHEADEnv = pkgs.emacsHEADEnv myEmacsPackages;
}
