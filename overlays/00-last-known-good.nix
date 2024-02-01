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
    # rev    = "known-good-20221221_180856";
    rev    = "f590aeafc4deddb5bb770a85bae208f36d2c72b3";
    sha256 = "0jr03wdwa2snxs9i6m1ndlh0gsz9m2crvfz5ar1xkracr9bma0n2";
  })
  httm
  recoll
  ;

  inherit (nixpkgs {
    # rev    = "known-good-20230815_094207";
    rev    = "6ac50c5df158c3cbe29c5111962e4c89daf1f929";
    sha256 = "sha256-trkGHaFfydle3MzKOFhGI4g1pY+j3s8xVsTNmztbLCI=";
  })
  pandoc
  mitmproxy
  ;

  inherit (nixpkgs {
    # rev    = "known-good-20231112_090312";
    rev    = "d9a676dbb008c2b98133e6ee81b6f92264f0a06e";
    sha256 = "sha256-jLGUC9mf9OE4uM+Hnelbw6u+xFNb1TWR+j/IeOwsikg=";
  })
  siege
  texinfo413
  ;

  inherit (nixpkgs {
    # rev    = "known-good-20231214_230317";
    rev    = "bd0b831a74765264d4f71035ad1d28728ba49edb";
    sha256 = "sha256-V4T55d2FxUTWH2sEWpp3du+cQZ/OibR/OYw2pN5y0b0=";
  })
  backblaze-b2
  ;

  inherit (nixpkgs {
    # rev    = "known-good-20240108_120429";
    rev    = "6498fa6d61651dbe0a101992e9dd34d939ce034a";
    sha256 = "sha256-EhaP/dBqlug/EQTJTnZB5ZnDOCvzyBmFes02jBI/Lxg=";
  })
  csvkit
  svg2tikz
  dovecot_fts_xapian
  libvirt
  ;
}
