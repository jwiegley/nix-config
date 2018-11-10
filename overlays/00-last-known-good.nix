self: super: {

lastKnownGood = import (super.fetchFromGitHub {
  owner  = "NixOS";
  repo   = "nixpkgs";
  rev    = "ee5f38dde279197aea00f01900c34556487bf717";
  sha256 = "01iy0sl610dnq0bqzhxwafb563h6qca3izv9afqq1c5x20xhhp92";
}) { config.allowUnfree = true; };

inherit (self.lastKnownGood) go_bootstrap;

lastKnownGood_2 = import (super.fetchFromGitHub {
  owner  = "NixOS";
  repo   = "nixpkgs";
  rev    = "2b962cc0c24163d492c699bba279b6a2be00dc2e";
  sha256 = "0cqh4d53if6x9lg9nr0rv0rsldx5bh13ainn86cjshdlnmijnhna";
}) { config.allowUnfree = true; };

inherit (self.lastKnownGood_2) xsv nix-index;

}
