{
  pkgs,
  src,
  agentResources,
  aiFlake,
  homeManagerLib,
  piGallery,
  inputs,
  testPkgsFor,
}:

let
  common = import ./home-manager-contract-common.nix {
    inherit
      pkgs
      src
      agentResources
      aiFlake
      homeManagerLib
      piGallery
      inputs
      testPkgsFor
      ;
  };

  # Input gating for config/ai and config/packages.nix. Pure evaluation with
  # no runtime harness, so this check asserts and then touches $out.
  checks = common.task11PackageChecks ++ common.task11AiperfChecks;
in
assert builtins.deepSeq checks true;

pkgs.runCommand "ai-home-manager-package-selection"
  {
    nativeBuildInputs = [
      pkgs.findutils
    ];
  }
  ''
    touch "$out"
  ''
