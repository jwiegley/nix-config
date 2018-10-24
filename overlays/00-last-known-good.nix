self: super: {

lastKnownGood = import (super.fetchFromGitHub {
  owner  = "NixOS";
  repo   = "nixpkgs";
  rev    = "ee5f38dde279197aea00f01900c34556487bf717";
  sha256 = "01iy0sl610dnq0bqzhxwafb563h6qca3izv9afqq1c5x20xhhp92";
}) { config.allowUnfree = true; };

inherit (self.lastKnownGood) go_bootstrap;

}
