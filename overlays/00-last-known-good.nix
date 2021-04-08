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

  darwin = super.darwin // {
    inherit ((nixpkgs {
      # known-good-20210325_234309
      rev    = "c91ae65e97a39a76272f6c3d0ecf630d71f7f421";
      sha256 = "0dhhkbhjspyh8nw9j1cnkfl9l1bhai3wylr2aiirgqxv3fsy5zgc";
    }).darwin)
      network_cmds
      ;
  };
}
