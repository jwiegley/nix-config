# overlays/00-last-known-good.nix
# Purpose: Pin specific packages to known-good nixpkgs revisions
_final: prev:

let
  nixpkgs = args@{ rev, sha256 }:
    import (prev.fetchFromGitHub (args // {
      owner = "NixOS";
      repo = "nixpkgs";
    })) { inherit (prev.stdenv.hostPlatform) system; };
in {
  inherit (nixpkgs {
    rev = "e1ebeec86b771e9d387dd02d82ffdc77ac753abc";
    sha256 = "sha256-g/da4FzvckvbiZT075Sb1/YDNDr+tGQgh4N8i5ceYMg=";
  })
    xquartz;
}
