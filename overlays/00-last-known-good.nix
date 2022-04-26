self: pkgs:

let nixpkgs = args@{ rev, sha256 }:
      import (pkgs.fetchFromGitHub (args // {
        owner = "NixOS";
        repo  = "nixpkgs"; })) {};
in {
  # inherit (nixpkgs {
  #   # rev    = "known-good-20190305_133437";
  #   rev    = "92ec809473e02f34aa756eb9b725266e4d2a7fbf";
  #   sha256 = "1f7vmhdipf0zz19lwx3ni0lmilhnild7r387a04ng92hnc27nnsv";
  # }) recoll;

  # inherit (nixpkgs {
  #   # rev    = "known-good-20220411_170044";
  #   rev    = "e09f2eba5e5ddefa34cb61c1e4127795a3a50b4a";
  #   sha256 = "179ibp9d20mw6lxrqp5g3x2vig7jdirdzqwz72k6z05b8nz0wp0f";
  # }) httpie;
}
