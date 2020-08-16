self: super:

let
  nixpkgs = { rev, sha256 }:
    import (super.fetchFromGitHub {
      owner = "NixOS";
      repo  = "nixpkgs";
      inherit rev sha256;
    }) { config.allowUnfree = true; };
in

{
  inherit (nixpkgs {
    # known-good-20190305_133437
    rev    = "b36dc66bfea6b0a733cf13bed85d80462d39c736";
    sha256 = "1f7vmhdipf0zz19lwx3ni0lmilhnild7r387a04ng92hnc27nnsv";
  })
    recoll
    socat2pre
    ;

  inherit (nixpkgs {
    # known-good-20200226_081157
    rev    = "e27b8d559ad97f6a29d5307c315308e4ee6f6eef";
    sha256 = "0xmr79k63mnbnvcxk1kbb8ama8ckgy7hjg7k5wnajhrx37zypqgv";
  })
    nix-diff
    ;

  inherit (nixpkgs {
    # known-good-20200419_174628
    rev    = "5460914bdd90082f655a2d930cac11b6d19cb825";
    sha256 = "1y8mbbc1m9lhnas5s0g91r4gn4snjmg6r1hs86pq98zz9fq8843x";
  })
    p7zip
    ;

  inherit (nixpkgs {
    # known-good-20200518_083459
    rev    = "e10c79407d7bacdeb477b7c204bdb82cf9ea16f2";
    sha256 = "1d9922zv3ja1bs4mp38fn316bmb94xz3714w5l957kmk9xy5mnn0";
  })
    zbar
    zziplib
    ;

  inherit (nixpkgs {
    # known-good-20200811_191740
    rev    = "8aa2cdc2d96a76f324e2ae07b2e4c0ef67867d4d";
    sha256 = "09d72jnizw0rdldc30z4319ai59hwcm1wfzm7ch1mdg4kdcv0knx";
  })
    csvkit
    httpie
    ;
}
