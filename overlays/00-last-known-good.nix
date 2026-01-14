self: pkgs:

let
  nixpkgs = args@{ rev, sha256 }:
    import (pkgs.fetchFromGitHub (args // {
      owner = "NixOS";
      repo = "nixpkgs";
    })) { };
in {
  inherit (nixpkgs {
    rev = "d9a676dbb008c2b98133e6ee81b6f92264f0a06e";
    sha256 = "sha256-jLGUC9mf9OE4uM+Hnelbw6u+xFNb1TWR+j/IeOwsikg=";
  })
    siege;

  inherit (nixpkgs {
    rev = "e1ebeec86b771e9d387dd02d82ffdc77ac753abc";
    sha256 = "sha256-g/da4FzvckvbiZT075Sb1/YDNDr+tGQgh4N8i5ceYMg=";
  })
    xquartz;

  inherit (nixpkgs {
    rev = "346dd96ad74dc4457a9db9de4f4f57dab2e5731d";
    sha256 = "sha256-7fsac/f7nh/VaKJ/qm3I338+wAJa/3J57cOGpXi0Sbg=";
  })
    git-machete;
}
