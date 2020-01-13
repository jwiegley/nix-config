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

  known-good-20190831_155518 = nixpkgs {
    rev    = "c4adeddb5f8e945517068968d06ea838b7c24bd3";
    sha256 = "1vpm73y7d0j2cviq0cgjwdj64h2v0c349capiyqf5f6071anx7d7";
  };

  known-good-20191113_070954 = nixpkgs {
    rev    = "620124b130c9e678b9fe9dd4a98750968b1f749a";
    sha256 = "0xgy2rn2pxii3axa0d9y4s25lsq7d9ykq30gvg2nzgmdkmy375rr";
  };

  known-good-20191130_091506 = nixpkgs {
    rev    = "c0a5a7ba47e1600b806781d1830d3bdba2ca0077";
    sha256 = "1hbm0hwggixd7mabgx840d9q49v5mja763w0p22d5h8yf5wb93fk";
  };

in
{
  inherit (known-good-20190305_133437) recoll socat2pre;

  inherit (known-good-20191113_070954) shared-mime-info;

  inherit (known-good-20191130_091506) nano;
}
