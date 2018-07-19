self: super: {

lastKnownGood = import (super.fetchFromGitHub {
  owner  = "NixOS";
  repo   = "nixpkgs";
  rev    = "2cbe52f42a2a7f0b2dfa687e432932305ee01d8e";
  sha256 = "0m2sfik3f9067m3v3pm4cjv3hdf56iwc3vymgh02qf8rqkh1s8cf";
}) { config.allowUnfree = true; };

inherit (self.lastKnownGood) aria2;

}
