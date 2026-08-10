{
  inputs,
  lib,
  pkgs,
  ...
}:

let
  system = pkgs.stdenv.hostPlatform.system;
  obrPackage =
    if inputs ? obr && inputs.obr ? packages && inputs.obr.packages ? ${system} then
      inputs.obr.packages.${system}.default
    else
      null;
in
{
  assertions = [
    {
      assertion = obrPackage != null;
      message = "managed home requires inputs.obr.packages.${system}.default";
    }
  ];

  home.packages = lib.optional (obrPackage != null) obrPackage;
}
