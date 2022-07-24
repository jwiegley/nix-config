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
  }) xquartz hub;
}
