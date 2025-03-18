self: pkgs:

let myEmacsPackages = import ./emacs.nix pkgs; in rec {
  emacsEnv = pkgs.emacsEnv myEmacsPackages;
}
