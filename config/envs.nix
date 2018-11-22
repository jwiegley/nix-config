self: pkgs:

let myEmacsPackages   = import ./emacs.nix pkgs; in
{
  emacsHEADEnv    = pkgs.emacsHEADEnv myEmacsPackages;
  emacs26Env      = pkgs.emacs26Env myEmacsPackages;
  emacs26DebugEnv = pkgs.emacs26DebugEnv myEmacsPackages;

  allEnvs = with self; [
    emacsHEADEnv
    emacs26Env
  ];
}
