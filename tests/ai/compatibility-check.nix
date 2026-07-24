{
  inputs,
  actual,
}:

let
  contract = import ./compatibility-contract.nix;
  lib = inputs.nixpkgs.lib;
  inputNames = lib.sort builtins.lessThan (
    builtins.attrNames (builtins.removeAttrs inputs [ "self" ])
  );
  require =
    path:
    lib.assertMsg (lib.hasAttrByPath path actual) "portable AI flake missing ${lib.concatStringsSep "." path}";
  requiredPaths =
    contract.topLevel
    ++ lib.concatMap (
      system:
      map (name: [
        "packages"
        system
        name
      ]) contract.packages
      ++ map (name: [
        "apps"
        system
        name
      ]) contract.apps
      ++ map (name: [
        "checks"
        system
        name
      ]) contract.checks
      ++ [
        [
          "devShells"
          system
          "default"
        ]
        [
          "formatter"
          system
        ]
      ]
    ) contract.systems;
  assertions = [
    (lib.assertMsg (inputNames == contract.inputs) "portable AI input contract changed")
    (lib.assertMsg (
      !(actual ? packages.x86_64-darwin)
    ) "portable AI flake exposes unsupported x86_64-darwin packages")
  ]
  ++ map require requiredPaths;
  checked = actual // {
    checks = lib.mapAttrs (
      system: checks:
      checks
      // {
        compatibility-contract =
          (import inputs.nixpkgs { inherit system; }).runCommand "ai-compatibility-contract" { }
            "touch $out";
      }
    ) actual.checks;
  };
in
assert builtins.deepSeq assertions true;
checked
