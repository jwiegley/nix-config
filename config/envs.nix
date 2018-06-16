self: pkgs:

let myEmacsPackages   = import ./emacs.nix pkgs;
    myHaskellPackages = import ./haskell.nix pkgs;
    myCoqPackages     = import ./coq.nix pkgs; in
{
  emacsHEADEnv    = pkgs.emacsHEADEnv myEmacsPackages;
  emacs26Env      = pkgs.emacs26Env myEmacsPackages;
  emacs26DebugEnv = pkgs.emacs26DebugEnv myEmacsPackages;

  ghc84Env        = pkgs.ghc84Env (myHaskellPackages 8.4);
  ghc82Env        = pkgs.ghc82Env (myHaskellPackages 8.2);
  ghc80Env        = pkgs.ghc80Env (myHaskellPackages 8.0);

  coqHEADEnv      = pkgs.coqHEADEnv myCoqPackages;
  coq88Env        = pkgs.coq88Env myCoqPackages;
  coq87Env        = pkgs.coq87Env myCoqPackages;
  coq86Env        = pkgs.coq86Env myCoqPackages;
  coq85Env        = pkgs.coq85Env myCoqPackages;
  coq84Env        = pkgs.coq84Env myCoqPackages;
}
