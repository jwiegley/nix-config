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
    # rev    = "known-good-20231112_090312";
    rev    = "d9a676dbb008c2b98133e6ee81b6f92264f0a06e";
    sha256 = "sha256-jLGUC9mf9OE4uM+Hnelbw6u+xFNb1TWR+j/IeOwsikg=";
  }) awscli2 clucene_core_2 dovecot figlet lean4 opam siege texinfo413;
}

# for i in ... ; do echo $i ; nix build -f '<darwin>' pkgs.${i} > /tmp/${i}.log 2>&1 || echo "${i}...FAILED" ; done
