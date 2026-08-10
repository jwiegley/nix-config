{
  inputs,
  pkgs,
  rootObr,
  src,
}:

let
  inherit (pkgs) lib;
  system = pkgs.stdenv.hostPlatform.system;
  directObr = inputs.obr.packages.${system}.default;
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
  present = evalObrModule { inherit (inputs) obr; };
  missing = evalObrModule { };
in
assert rootLock.nodes.root.inputs ? obr;
assert !(portableLock.nodes.root.inputs ? obr);
assert !(builtins.elem "obr" portableContract.inputs);
assert !(builtins.elem "obr" portableContract.packages);
assert !(portablePackages ? obr);
assert rootObr.drvPath == directObr.drvPath;
assert
  present.assertions == [
    {
      assertion = true;
      message = "managed home requires inputs.obr.packages.${system}.default";
    }
  ];
assert present.home.packages == [ directObr ];
assert
  missing.assertions == [
    {
      assertion = false;
      message = "managed home requires inputs.obr.packages.${system}.default";
    }
  ];
assert missing.home.packages == [ ];
pkgs.runCommand "obr-ownership" { } "touch $out"
