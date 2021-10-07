self: pkgs:

let myEmacsPackages = import ./emacs.nix pkgs; in rec {
  emacs27Env  = pkgs.emacs27Env  myEmacsPackages;
  emacsERCEnv = pkgs.emacsERCEnv myEmacsPackages;

  inherit (pkgs) ledgerPy2Env ledgerPy3Env;

  projects-env = pkgs.stdenv.mkDerivation rec {
    name = "projects";
    srcs = [
      # (import ~/doc/johnwiegley { inherit pkgs; })
      # (import ~/doc/newartisans { inherit pkgs; })

      (import ~/dfinity/master/rs {}).shell
      (import ~/dfinity/master/hs/analyzer/shell.nix {})
      (import ~/dfinity/formal-models/coq-governance {}).env
      (import ~/dfinity/formal-models/icp-forecast { inherit pkgs; returnShellEnv = true; })

      (import ~/src/agda/adders-and-arrows { inherit pkgs; }).env
      (import ~/src/agda/plfa { inherit pkgs; }).env
      (import ~/src/category-theory { inherit pkgs; }).env
      (import ~/src/ltl/coq { inherit pkgs; }).env
      (import ~/src/ltl/simple-ltl { inherit pkgs; returnShellEnv = true; })
      (import ~/src/notes/coq { inherit pkgs; }).env
      (import ~/src/notes/haskell { inherit pkgs; returnShellEnv = true; })
      (import ~/src/notes/rust { inherit pkgs; returnShellEnv = true; })
      (import ~/src/trade-journal { inherit pkgs; returnShellEnv = true; })
      (import ~/src/sitebuilder { inherit pkgs; returnShellEnv = true; })
      # (import ~/src/wallet { inherit pkgs; }).shell
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
