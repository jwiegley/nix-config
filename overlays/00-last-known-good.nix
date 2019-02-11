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

gitAndTools = super.gitAndTools // {

inherit ((nixpkgs { # known-good-20190131_115636
  rev    = "120eab94e0981758a1c928ff81229cd802053158";
  sha256 = "0qk6k8gxx5xlkyg05dljywj5wx5fvrc3dzp4v2h6ab83b7zwg813"; }).gitAndTools)

  git-annex;

};

}
