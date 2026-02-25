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

  # Pin packages to previous nixpkgs-unstable revision where they built.
  # mitmproxy 12.2.1: dependency upper bounds exceeded (aioquic, asgiref, etc.)
  # gemini-cli 0.29.7: node-pty fails to compile with Node.js 24.13.0
  # backblaze-b2 4.5.1: docutils version constraint not satisfied
  inherit
    (nixpkgs {
      rev = "bcc4a9d9533c033d806a46b37dc444f9b0da49dd";
      sha256 = "sha256-K7Dg9TQ0mOcAtWTO/FX/FaprtWQ8BmEXTpLIaNRhEwU=";
    })
    mitmproxy
    gemini-cli
    backblaze-b2
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
