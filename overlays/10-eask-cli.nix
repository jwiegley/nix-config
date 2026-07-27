# Cross-platform Eask package, independent of Darwin compatibility pins.
_final: prev: {
  eask-cli = prev.buildNpmPackage rec {
    pname = "eask-cli";
    version = "0.12.9";
    src = prev.fetchFromGitHub {
      owner = "emacs-eask";
      repo = "cli";
      rev = version;
      hash = "sha256-jYdx+MYgUop01MzcKPxtm+ZW6lsy9eCqH00uQd8imRw=";
    };
    npmDepsHash = "sha256-Xj68un97I8xtAY3RXEq8PNC8ZOZ+NWg6SblnmKzHGMo=";
    dontBuild = true;
    meta = with prev.lib; {
      description = "CLI for building, running, testing, and managing Emacs Lisp dependencies";
      homepage = "https://emacs-eask.github.io/";
      license = licenses.gpl3Plus;
      mainProgram = "eask";
    };
  };
}
