self: pkgs:

let myEmacsPackages = import ./emacs.nix pkgs; in
rec {
  # emacs26Env      = pkgs.emacs26Env      myEmacsPackages;
  # emacs26DebugEnv = pkgs.emacs26DebugEnv myEmacsPackages;
  # emacs27DebugEnv = pkgs.emacs27DebugEnv myEmacsPackages;
  # emacsHEADEnv    = pkgs.emacsHEADEnv    myEmacsPackages;

  emacs27Env  = pkgs.emacs27Env  myEmacsPackages;
  emacsERCEnv = pkgs.emacsERCEnv myEmacsPackages;

  inherit (pkgs) ledgerPy2Env ledgerPy3Env;

  projects-env = pkgs.stdenv.mkDerivation rec {
    name = "projects";
    srcs = [
      (import ~/src/agda/plfa {}).env
      (import ~/src/category-theory {}).env
      (import ~/src/hnix { returnShellEnv = true; })
      (import ~/src/ltl/simple-ltl { returnShellEnv = true; })
      (import ~/src/sitebuilder { returnShellEnv = true; })
      (import ~/src/thinkorswim/trade-journal { returnShellEnv = true; })
    ];
    phases = ["buildPhase" "installPhase"];
    buildPhase = "true";
    installPhase = ''
      mkdir $out
    '' + (pkgs.stdenv.lib.concatStrings (builtins.map (src: ''
      ln -s ${src} $out
    '') srcs));
  };
}
