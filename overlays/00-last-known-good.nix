self: super:

let nixpkgs = args@{ rev, sha256 }:
      import (super.fetchFromGitHub (args // {
        owner = "NixOS";
        repo  = "nixpkgs"; })) {};
in {
  inherit (nixpkgs {
    # rev    = "known-good-20190305_133437";
    rev    = "92ec809473e02f34aa756eb9b725266e4d2a7fbf";
    sha256 = "1f7vmhdipf0zz19lwx3ni0lmilhnild7r387a04ng92hnc27nnsv";
  }) recoll;
}
