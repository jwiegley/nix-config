{
  inputs,
  pkgs,
  rootObr,
  src,
}:

let
  inherit (pkgs) lib;
  system = pkgs.stdenv.hostPlatform.system;
  obrNode = rootLock.nodes.${rootLock.nodes.root.inputs.obr};
  directObr = (import "${src}/packages/source-project-apps.nix" { inherit inputs pkgs; }).obr;
  sourceProjectInputNames =
    (import "${src}/config/packages.nix" {
      hostname = "hera";
      inherit inputs pkgs;
    }).userPackageInputNames;
  portablePackages = inputs.nix-config-ai.packages.${system};
  portableContract = import "${src}/test/ai/compatibility-contract.nix";
  rootLock = builtins.fromJSON (builtins.readFile "${src}/flake.lock");
  portableLock = builtins.fromJSON (builtins.readFile "${src}/config/ai/flake.lock");
  evalObrModule =
    suppliedInputs:
    (lib.evalModules {
      specialArgs = {
        inputs = suppliedInputs;
        inherit pkgs;
      };
      modules = [
        {
          options = {
            assertions = lib.mkOption {
              type = lib.types.listOf (
                lib.types.submodule {
                  options = {
                    assertion = lib.mkOption { type = lib.types.bool; };
                    message = lib.mkOption { type = lib.types.str; };
                  };
                }
              );
              default = [ ];
            };
            home.packages = lib.mkOption {
              type = lib.types.listOf lib.types.package;
              default = [ ];
            };
          };
        }
        (import "${src}/config/obr.nix")
      ];
    }).config;
  present = evalObrModule { inherit (inputs) obr rust-overlay; };
  missingObr = evalObrModule { inherit (inputs) rust-overlay; };
  missingRustOverlay = evalObrModule { inherit (inputs) obr; };
in
assert rootLock.nodes.root.inputs ? obr;
assert !(obrNode.flake or true);
assert !(obrNode ? inputs);
assert inputs.obr ? outPath;
assert !(inputs.obr ? packages);
assert !(portableLock.nodes.root.inputs ? obr);
assert !(builtins.elem "obr" portableContract.inputs);
assert !(builtins.elem "obr" portableContract.packages);
assert !(portablePackages ? obr);
assert !(builtins.elem "obr" sourceProjectInputNames);
assert rootObr.drvPath == directObr.drvPath;
assert
  present.assertions == [
    {
      assertion = true;
      message = "managed home requires inputs.obr.outPath and inputs.rust-overlay.outPath";
    }
  ];
assert present.home.packages == [ directObr ];
assert
  missingObr.assertions == [
    {
      assertion = false;
      message = "managed home requires inputs.obr.outPath and inputs.rust-overlay.outPath";
    }
  ];
assert missingObr.home.packages == [ ];
assert missingRustOverlay.assertions == missingObr.assertions;
assert missingRustOverlay.home.packages == [ ];
pkgs.runCommand "obr-ownership" { } "touch $out"
