self: pkgs:

let nixpkgs = args@{ rev, sha256 }:
      import (pkgs.fetchFromGitHub (args // {
        owner = "NixOS";
        repo  = "nixpkgs"; })) {};
in {
  inherit (nixpkgs {
    rev    = "d9a676dbb008c2b98133e6ee81b6f92264f0a06e";
    sha256 = "sha256-jLGUC9mf9OE4uM+Hnelbw6u+xFNb1TWR+j/IeOwsikg=";
  })
  siege
  ;

  inherit (nixpkgs {
    rev    = "6498fa6d61651dbe0a101992e9dd34d939ce034a";
    sha256 = "sha256-EhaP/dBqlug/EQTJTnZB5ZnDOCvzyBmFes02jBI/Lxg=";
  })
  lnav
  ;

  inherit (nixpkgs {
    rev    = "038fb464fcfa79b4f08131b07f2d8c9a6bcc4160";
    sha256 = "sha256-Ul3rIdesWaiW56PS/Ak3UlJdkwBrD4UcagCmXZR9Z7Y=";
  })
  texinfo4
  ;

  inherit (nixpkgs {
    rev    = "2d2a9ddbe3f2c00747398f3dc9b05f7f2ebb0f53";
    sha256 = "sha256-B5WRZYsRlJgwVHIV6DvidFN7VX7Fg9uuwkRW9Ha8z+w=";
  })
  libvirt
  multitail
  nix-diff
  opensc
  xquartz
  ;
}
