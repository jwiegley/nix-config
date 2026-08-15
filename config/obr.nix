{
  inputs,
  lib,
  pkgs,
  ...
}:

let
  sourceProjectApps = import ../packages/source-project-apps.nix { inherit inputs pkgs; };
  hasObrInputs =
    inputs ? obr && inputs.obr ? outPath && inputs ? rust-overlay && inputs.rust-overlay ? outPath;
  obrPackage = if hasObrInputs then sourceProjectApps.obr else null;
in
{
  assertions = [
    {
      assertion = obrPackage != null;
      message = "managed home requires inputs.obr.outPath and inputs.rust-overlay.outPath";
    }
  ];

  home.packages = lib.optional (obrPackage != null) obrPackage;
}
