{ lib, runCommand }:

let
  overlay = import ../../overlays/30-git-tools.nix { };
  mkTea = version: {
    inherit version;
    overrideAttrs =
      transform:
      transform { preBuild = "upstream-pre-build\n"; }
      // {
        marker = "overridden";
      };
  };
  legacy =
    (overlay { } {
      inherit lib;
      tea = mkTea "0.14.0";
    }).tea;
  current =
    (overlay { } {
      inherit lib;
      tea = {
        version = "0.15.1";
        marker = "upstream";
        overrideAttrs = _: throw "Tea 0.15+ used retired go-git patch";
      };
    }).tea;
in
assert legacy.marker == "overridden";
assert lib.hasPrefix "upstream-pre-build\n" legacy.preBuild;
assert lib.hasInfix "repository_extensions.go" legacy.preBuild;
assert current.marker == "upstream";
runCommand "git-tools-tea-compat" { } "touch $out"
