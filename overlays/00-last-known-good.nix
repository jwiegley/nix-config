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
    # known-good-20200811_191740
    rev    = "8aa2cdc2d96a76f324e2ae07b2e4c0ef67867d4d";
    sha256 = "09d72jnizw0rdldc30z4319ai59hwcm1wfzm7ch1mdg4kdcv0knx";
  })
    csvkit
    xquartz
    ;
}
