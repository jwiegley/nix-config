self: pkgs:

let nixpkgs = args@{ rev, sha256 }:
      import (pkgs.fetchFromGitHub (args // {
        owner = "NixOS";
        repo  = "nixpkgs"; })) {};
in {
  gitAndTools = pkgs.gitAndTools // {
    inherit ((nixpkgs {
      # rev    = "known-good-20221221_180856";
      rev    = "f590aeafc4deddb5bb770a85bae208f36d2c72b3";
      sha256 = "0jr03wdwa2snxs9i6m1ndlh0gsz9m2crvfz5ar1xkracr9bma0n2";
    }).gitAndTools) git-annex;
  };

  inherit (nixpkgs {
    # rev    = "known-good-20230815_094207";
    rev    = "6ac50c5df158c3cbe29c5111962e4c89daf1f929";
    sha256 = "sha256-trkGHaFfydle3MzKOFhGI4g1pY+j3s8xVsTNmztbLCI=";
  }) pandoc;

  inherit (nixpkgs {
    # rev    = "known-good-20231019_094849";
    rev    = "4af7d5a24cb5ab3d1e3a9720e679b416707847b2";
    sha256 = "sha256-trkGHaFfydle3MzKOFhGI4g1pY+j3s8xVsTNmztbLCI=";
  }) asymptote csvkit mitmproxy;
}
