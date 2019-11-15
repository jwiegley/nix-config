self: pkgs:

let myEmacsPackages   = import ./emacs.nix pkgs; in
{
  emacs26Env      = pkgs.emacs26Env myEmacsPackages;
  # emacs26DebugEnv = pkgs.emacs26DebugEnv myEmacsPackages;
  # emacsHEADEnv    = pkgs.emacsHEADEnv myEmacsPackages;
  emacsERCEnv     = pkgs.emacsERCEnv myEmacsPackages;

  allEnvs = with self; [
    emacs26Env
    emacsERCEnv
  ];
}
