self: super:

let nixpkgs = args@{ rev, sha256 }:
      import (super.fetchFromGitHub (args // {
        owner = "NixOS";
        repo  = "nixpkgs"; })) {};
in {
  inherit (nixpkgs {
    # rev    = "known-good-20190305_133437";
    rev    = "92ec809473e02f34aa756eb9b725266e4d2a7fbf";
    sha256 = "1f7vmhdipf0zz19lwx3ni0lmilhnild7r387a04ng92hnc27nnsv";
  }) recoll;

  inherit (nixpkgs {
    # rev    = "known-good-20211122_233757";
    rev    = "91e1ec3220ce0c47577d4b3d880ef9b1ffee3d3e";
    sha256 = "sha256-Wmm+1JLzOEtDwY6FQpuK35vBYXBZVngmU8I97fVbaqE=";
  }) qemu;

  inherit (nixpkgs {
    # rev    = "known-good-20211203_093237";
    rev    = "08f61628174fa4b5c500622ce93138bd1063cdbf";
    sha256 = "sha256-uaLfhJ5J7CMs4ikrtPi8yccg5zAIuwdUeokhKwn19k8=";
  }) socat;

  inherit (nixpkgs {
    # rev    = "known-good-20220210_135242";
    rev    = "59d4fd41853dc2654fc699f016d2da9dae026d12";
    sha256 = "sha256-KkLh7B0dciR0YyVIY/RLrDJ5+6vopr62Q3l8nk/vSsU=";
  }) python3Packages backblaze-b2 httpie;
}
