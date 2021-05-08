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
    backblaze-b2
    csvkit
    ;

  inherit (nixpkgs {
    # known-good-20210427_194036
    rev    = "6ff596863b1497fd2114a3f4814e16af7385f86c";
    sha256 = "1bc624inm21wl6s9b4nmn495j25yab1bvn3jc3f1mjfmcrbvm1gd";
  })
    subversion
    qemu
    ;
}
