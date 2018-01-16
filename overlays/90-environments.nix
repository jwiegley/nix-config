self: super: {

myBuildEnvs = with super; stdenv.mkDerivation {
  name = "coqHEAD";
  buildInputs = [
    coq84Env
    coq85Env
    coq86Env
    coq87Env
    coqHEADEnv
    emacs25Env
    emacs26Env
    emacs26DebugEnv
    emacsHEADEnv
    ghc80Env
    ghc80ProfEnv
    ghc82Env
    ghc82ProfEnv
    ledgerPy2Env
    ledgerPy3Env
  ];
};

}
