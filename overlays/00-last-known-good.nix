self: super:

let
  nixpkgs = { rev, sha256 }:
    import (super.fetchFromGitHub {
      owner = "NixOS";
      repo  = "nixpkgs";
      inherit rev sha256;
    }) { config.allowUnfree = true; };

  known-good-20190305_133437 = nixpkgs {
    rev    = "b36dc66bfea6b0a733cf13bed85d80462d39c736";
    sha256 = "1f7vmhdipf0zz19lwx3ni0lmilhnild7r387a04ng92hnc27nnsv";
  };

  known-good-20191113_070954 = nixpkgs {
    rev    = "620124b130c9e678b9fe9dd4a98750968b1f749a";
    sha256 = "0xgy2rn2pxii3axa0d9y4s25lsq7d9ykq30gvg2nzgmdkmy375rr";
  };
in {
  inherit (known-good-20190305_133437) recoll;
  inherit (known-good-20190305_133437) socat2pre;
  inherit (known-good-20191113_070954) shared-mime-info;
}
