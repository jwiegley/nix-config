self: pkgs:

let myEmacsPackages   = import ./emacs.nix pkgs;
    myHaskellPackages = import ./haskell.nix pkgs;
    myCoqPackages     = import ./coq.nix pkgs; in
{
  emacsHEADEnv    = pkgs.emacsHEADEnv myEmacsPackages;
  emacs26Env      = pkgs.emacs26Env myEmacsPackages;
  emacs26DebugEnv = pkgs.emacs26DebugEnv myEmacsPackages;
  emacs25Env      = pkgs.emacs25Env myEmacsPackages;

  ghcHEADEnv      = pkgs.ghcHEADEnv myHaskellPackages;
  ghcHEADProfEnv  = pkgs.ghcHEADProfEnv myHaskellPackages;
  ghc82Env        = pkgs.ghc82Env myHaskellPackages;
  ghc82ProfEnv    = pkgs.ghc82ProfEnv myHaskellPackages;
  ghc80Env        = pkgs.ghc80Env myHaskellPackages;
  ghc80ProfEnv    = pkgs.ghcHEADEnv myHaskellPackages;

  coqHEADEnv      = pkgs.coqHEADEnv myCoqPackages;
  coq87Env        = pkgs.coq87Env myCoqPackages;
  coq86Env        = pkgs.coq86Env myCoqPackages;
  coq85Env        = pkgs.coq85Env myCoqPackages;
  coq84Env        = pkgs.coq84Env myCoqPackages;
}
