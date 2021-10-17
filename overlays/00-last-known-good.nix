self: super:

let nixpkgs = args@{ rev, sha256 }:
      import (super.fetchFromGitHub (args // {
        owner = "NixOS";
        repo  = "nixpkgs"; })) {};
in {
  inherit (nixpkgs {
    rev    = "known-good-20190305_133437";
    sha256 = "1f7vmhdipf0zz19lwx3ni0lmilhnild7r387a04ng92hnc27nnsv";
  }) recoll;

  inherit (nixpkgs {
    rev    = "known-good-20210829_140352";
    sha256 = "08vxysz4pq9fzdhgj7igkmkcs95ndnal9i6mhs0dpmzpirw12sn1";
  }) backblaze-b2;
}
