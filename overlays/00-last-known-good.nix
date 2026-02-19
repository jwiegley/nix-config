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
    )) { inherit (prev.stdenv.hostPlatform) system; };
in
{
  inherit
    (nixpkgs {
      rev = "e1ebeec86b771e9d387dd02d82ffdc77ac753abc";
      sha256 = "sha256-g/da4FzvckvbiZT075Sb1/YDNDr+tGQgh4N8i5ceYMg=";
    })
    xquartz
    ;

  eask-cli = prev.buildNpmPackage rec {
    pname = "eask-cli";
    version = "0.12.8";
    src = prev.fetchFromGitHub {
      owner = "emacs-eask";
      repo = "cli";
      rev = version;
      hash = "sha256-eH46NlHQs+OVbc3WVUKHQGgXi9rvFMTrbd3UB8WCB6k=";
    };
    npmDepsHash = "sha256-U/VKtefL31FNYUegt8+Qg2jM6fx4cX660UcNqGsWMOc=";
    dontBuild = true;
    meta = with prev.lib; {
      description = "CLI for building, running, testing, and managing your Emacs Lisp dependencies";
      homepage = "https://emacs-eask.github.io/";
      license = licenses.gpl3Plus;
      mainProgram = "eask";
    };
  };
}
