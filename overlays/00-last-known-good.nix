self: super:

let
  nixpkgs = { rev, sha256 }:
    import (super.fetchFromGitHub {
      owner  = "NixOS";
      repo   = "nixpkgs";
      inherit rev sha256;
    }) { config.allowUnfree = true; }; in

{

inherit (nixpkgs { # known-good-20181014_234648
  rev    = "ee5f38dde279197aea00f01900c34556487bf717";
  sha256 = "01iy0sl610dnq0bqzhxwafb563h6qca3izv9afqq1c5x20xhhp92"; })

  go_bootstrap;

inherit (nixpkgs { # known-good-20181022_153106
  rev    = "2b962cc0c24163d492c699bba279b6a2be00dc2e";
  sha256 = "0cqh4d53if6x9lg9nr0rv0rsldx5bh13ainn86cjshdlnmijnhna"; })

  xsv nix-index;

inherit (nixpkgs { # known-good-20181208_134904
  rev    = "61c3169a0e17d789c566d5b241bfe309ce4a6275";
  sha256 = "0qbycg7wkb71v20rchlkafrjfpbk2fnlvvbh3ai9pyfisci5wxvq"; })

  zbar xquartz;

}
