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
    rev    = "038fb464fcfa79b4f08131b07f2d8c9a6bcc4160";
    sha256 = "sha256-Ul3rIdesWaiW56PS/Ak3UlJdkwBrD4UcagCmXZR9Z7Y=";
  })
  texinfo4
  ;

  # inherit (nixpkgs {
  #   rev    = "4bc9c909d9ac828a039f288cf872d16d38185db8";
  #   sha256 = "sha256-nIYdTAiKIGnFNugbomgBJR+Xv5F1ZQU+HfaBqJKroC0=";
  # })
  # asymptote
  # clisp
  # ;

  inherit (nixpkgs {
    rev    = "9a5db3142ce450045840cc8d832b13b8a2018e0c";
    sha256 = "sha256-pUvLijVGARw4u793APze3j6mU1Zwdtz7hGkGGkD87qw=";
  })
  mitmproxy
  httpie
  xquartz
  basedpyright
  backblaze-b2
  ;
}
