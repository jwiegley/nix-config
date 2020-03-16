self: pkgs:

let myEmacsPackages   = import ./emacs.nix pkgs; in
{
  emacs26Env = pkgs.emacs26Env myEmacsPackages;
  # emacs26DebugEnv = pkgs.emacs26DebugEnv myEmacsPackages;
  emacs27Env = pkgs.emacs27Env myEmacsPackages;
  # emacs27DebugEnv = pkgs.emacs27DebugEnv myEmacsPackages;
  emacsERCEnv = pkgs.emacsERCEnv myEmacsPackages;
  # emacsHEADEnv = pkgs.emacsHEADEnv myEmacsPackages;

  allEnvs = with self; [
    emacs26Env
    # emacs26DebugEnv
    # emacs27Env
    # emacs27DebugEnv
    emacsERCEnv
    # emacsHEADEnv
  ];
}
