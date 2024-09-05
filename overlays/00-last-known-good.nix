self: pkgs:

let nixpkgs = args@{ rev, sha256 }:
      import (pkgs.fetchFromGitHub (args // {
        owner = "NixOS";
        repo  = "nixpkgs"; })) {};
in {
  inherit (nixpkgs {
    # rev    = "known-good-20230815_094207";
    rev    = "6ac50c5df158c3cbe29c5111962e4c89daf1f929";
    sha256 = "sha256-trkGHaFfydle3MzKOFhGI4g1pY+j3s8xVsTNmztbLCI=";
  })
  mitmproxy
  ;

  inherit (nixpkgs {
    # rev    = "known-good-20231112_090312";
    rev    = "d9a676dbb008c2b98133e6ee81b6f92264f0a06e";
    sha256 = "sha256-jLGUC9mf9OE4uM+Hnelbw6u+xFNb1TWR+j/IeOwsikg=";
  })
  siege
  ;

  inherit (nixpkgs {
    # rev    = "known-good-20240108_120429";
    rev    = "6498fa6d61651dbe0a101992e9dd34d939ce034a";
    sha256 = "sha256-EhaP/dBqlug/EQTJTnZB5ZnDOCvzyBmFes02jBI/Lxg=";
  })
  lnav
  csvkit
  svg2tikz                      # python dependency build stalls
  ;

  inherit (nixpkgs {
    # rev    = "known-good-20240507_090322";
    rev    = "038fb464fcfa79b4f08131b07f2d8c9a6bcc4160";
    sha256 = "sha256-Ul3rIdesWaiW56PS/Ak3UlJdkwBrD4UcagCmXZR9Z7Y=";
  })
  texinfo4
  watchman
  ;
}
