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

  inherit (nixpkgs {
    # rev    = "known-good-20210829_140352";
    rev    = "c71c411d8f9ec5bd746fcd925555cee5b3cdd297";
    sha256 = "08vxysz4pq9fzdhgj7igkmkcs95ndnal9i6mhs0dpmzpirw12sn1";
  }) backblaze-b2;

  inherit (nixpkgs {
    # rev    = "known-good-20211122_233757";
    rev    = "91e1ec3220ce0c47577d4b3d880ef9b1ffee3d3e";
    sha256 = "sha256-Wmm+1JLzOEtDwY6FQpuK35vBYXBZVngmU8I97fVbaqE=";
  }) qemu;
}
