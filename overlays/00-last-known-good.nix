# overlays/00-last-known-good.nix
# Purpose: Pin specific packages to known-good nixpkgs revisions
_final: prev:

let
  _nixpkgs =
    args@{ rev, sha256 }:
    import (prev.fetchFromGitHub (
      args
      // {
        owner = "NixOS";
        repo = "nixpkgs";
      }
    )) { localSystem = prev.stdenv.hostPlatform.system; };
in
{
  # inherit
  #   (nixpkgs {
  #     rev = "e1ebeec86b771e9d387dd02d82ffdc77ac753abc";
  #     sha256 = "sha256-g/da4FzvckvbiZT075Sb1/YDNDr+tGQgh4N8i5ceYMg=";
  #   })
  #   xquartz
  #   ;

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
