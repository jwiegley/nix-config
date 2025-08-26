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
    rev    = "9b008d60392981ad674e04016d25619281550a9d";
    sha256 = "sha256-mgFxAPLWw0Kq+C8P3dRrZrOYEQXOtKuYVlo9xvPntt8=";
  })
  aider-chat
  mitmproxy
  ;
}
