self: pkgs:

let nixpkgs = args@{ rev, sha256 }:
      import (pkgs.fetchFromGitHub (args // {
        owner = "NixOS";
        repo  = "nixpkgs"; })) {};
in {
  inherit (nixpkgs {
    # rev    = "known-good-20220629_100756";
    rev    = "334068fdfa9ab8824f735542e8946a705189c258";
    sha256 = "0z1xqa0pmf6l56354i376wggniqqkw9g49k173156mb39fvx6hrx";
  }) xquartz;

  inherit (nixpkgs {
    # rev    = "known-good-20220815_094029";
    rev    = "5ae5d44e5ded42ba715be07002325487408d36ae";
    sha256 = "08mxlbs32m844vp6vnirgcd09qm9hmh1ifmjpb34jrppjdmal069";
  }) biber fd httpie;
}
