self: pkgs:

let myEmacsPackages = import ./emacs.nix pkgs; in
{
  # emacs26Env      = pkgs.emacs26Env      myEmacsPackages;
  # emacs26DebugEnv = pkgs.emacs26DebugEnv myEmacsPackages;
  # emacs27DebugEnv = pkgs.emacs27DebugEnv myEmacsPackages;
  # emacsHEADEnv    = pkgs.emacsHEADEnv    myEmacsPackages;

  emacs27Env  = pkgs.emacs27Env  myEmacsPackages;
  emacsERCEnv = pkgs.emacsERCEnv myEmacsPackages;

  inherit (pkgs) ledgerPy2Env ledgerPy3Env;

  category-theory-env = (import ~/src/category-theory {}).env;
  trade-journal-env   = import ~/src/thinkorswim/trade-journal { returnShellEnv = true; };
}
