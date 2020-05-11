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

  known-good-20200226_081157 = nixpkgs {
    rev    = "e27b8d559ad97f6a29d5307c315308e4ee6f6eef";
    sha256 = "0xmr79k63mnbnvcxk1kbb8ama8ckgy7hjg7k5wnajhrx37zypqgv";
  };

  known-good-20200419_174628 = nixpkgs {
    rev    = "5460914bdd90082f655a2d930cac11b6d19cb825";
    sha256 = "1y8mbbc1m9lhnas5s0g91r4gn4snjmg6r1hs86pq98zz9fq8843x";
  };
in

{
  inherit (known-good-20190305_133437)
    recoll
    socat2pre
    ;

  inherit (known-good-20200226_081157)
    nix-diff
    ;

  inherit (known-good-20200419_174628)
    p7zip
    ;
}
