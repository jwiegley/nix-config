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
    # known-good-20210422_091739
    rev    = "f41dd45874e0113843f00a59c0b67c1609eeddf8";
    sha256 = "0hwfvj50g84h8kcnmv2sz1z7n505s7kd2096lf23fbbpd6i4zb7m";
  })
    csvkit
    ;

  inherit (nixpkgs {
    # known-good-20210619_090958
    rev    = "961d51aad2dd3838fccdf8c97a276bbd247b3040";
    sha256 = "0xnvx8aqi2n87zvifvmfk28fzxgn4yxqbvspszscsd7nmr9v8xj7";
  })
    dovecot
    dovecot_pigeonhole
    exiv2
    nix-prefetch-scripts
    squashfsTools
    ;

  inherit (nixpkgs {
    # known-good-20210829_140352
    rev    = "f29257b3ba2b0dbba291cb7c6a10becee932543f";
    sha256 = "08vxysz4pq9fzdhgj7igkmkcs95ndnal9i6mhs0dpmzpirw12sn1";
  })
    backblaze-b2
    ;
}
