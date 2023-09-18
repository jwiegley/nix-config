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

  gitAndTools = pkgs.gitAndTools // {
    inherit ((nixpkgs {
      # rev    = "known-good-20221221_180856";
      rev    = "f590aeafc4deddb5bb770a85bae208f36d2c72b3";
      sha256 = "0jr03wdwa2snxs9i6m1ndlh0gsz9m2crvfz5ar1xkracr9bma0n2";
    }).gitAndTools) git-annex;
  };

  inherit (nixpkgs {
    # rev    = "known-good-20230409_220321";
    rev    = "e1586b80a559beb47279c96d66ac6e8a216f58fe";
    sha256 = "1fq11aq0h0795lrrkr56nv0lfr2saljcnypj7c9h8zrq85k82ic1";
  }) vim-full squashfsTools;

  inherit (nixpkgs {
    # rev    = "known-good-20230815_094207";
    rev    = "6ac50c5df158c3cbe29c5111962e4c89daf1f929";
    sha256 = "sha256-trkGHaFfydle3MzKOFhGI4g1pY+j3s8xVsTNmztbLCI=";
  }) pandoc;
}
