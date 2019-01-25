self: super:

let
  nixpkgs = { rev, sha256 }:
    import (super.fetchFromGitHub {
      owner  = "NixOS";
      repo   = "nixpkgs";
      inherit rev sha256;
    }) { config.allowUnfree = true; }; in

{

inherit (nixpkgs { # known-good-20181208_134904
  rev    = "61c3169a0e17d789c566d5b241bfe309ce4a6275";
  sha256 = "0qbycg7wkb71v20rchlkafrjfpbk2fnlvvbh3ai9pyfisci5wxvq"; })

  zbar xquartz;

}
