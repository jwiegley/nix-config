# overlays/00-last-known-good.nix
# Purpose: Pin specific packages to known-good nixpkgs revisions
_final: prev:

let
  nixpkgs =
    args@{ rev, sha256 }:
    import (prev.fetchFromGitHub (
      args
      // {
        owner = "NixOS";
        repo = "nixpkgs";
      }
    )) { localSystem = prev.stdenv.hostPlatform.system; };

  # Last good nixpkgs rev before the 2026-04-23 bump (rev 01fbdeef...)
  # broke several Darwin builds:
  #   - ntp: configure can't find pthreads on Darwin SDK 14.4
  #   - aprutil: sdbm_pair.c K&R decls rejected by clang C23 defaults
  #   - libcdio-paranoia: ./getopt.h K&R decl conflicts with unistd.h
  #   - python3Packages.av: pythonImportsCheckPhase OOMs loading ffmpeg syms
  #   - python3Packages.openai-whisper: ffmpeg-subprocess test fails in sandbox
  lastGood = nixpkgs {
    rev = "b86751bc4085f48661017fa226dee99fab6c651b";
    sha256 = "sha256-a8BYi3mzoJ/AcJP8UldOx8emoPRLeWqALZWu4ZvjPXw=";
  };
in
{
  inherit (lastGood)
    ntp
    aprutil
    libcdio-paranoia
    ;

  pythonPackagesExtensions = (prev.pythonPackagesExtensions or [ ]) ++ [
    (
      pfinal: pprev:
      (prev.lib.optionalAttrs (pprev ? av) {
        inherit (lastGood.${pprev.python.pythonAttr}.pkgs) av;
      })
      // (prev.lib.optionalAttrs (pprev ? openai-whisper) {
        inherit (lastGood.${pprev.python.pythonAttr}.pkgs) openai-whisper;
      })
    )
  ];

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
      description = "CLI for building, running, testing, and managing your Emacs Lisp dependencies";
      homepage = "https://emacs-eask.github.io/";
      license = licenses.gpl3Plus;
      mainProgram = "eask";
    };
  };
}
