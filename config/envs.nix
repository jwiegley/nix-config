self: pkgs:

let myEmacsPackages = import ./emacs.nix pkgs; in rec {
  emacs27Env  = pkgs.emacs27Env  myEmacsPackages;
  emacsERCEnv = pkgs.emacsERCEnv myEmacsPackages;

  inherit (pkgs) ledgerPy2Env ledgerPy3Env;

  projects-env = pkgs.stdenv.mkDerivation rec {
    name = "projects";
    srcs = [
      (import ~/dfinity/master/rs {}).shell
      (import ~/dfinity/consensus-model {}).env
      (import ~/dfinity/consensus-model/reference { returnShellEnv = true; })

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
    '' + (pkgs.lib.concatStrings (builtins.map (src: ''
      ln -s ${src} $out
    '') srcs));
  };
}
