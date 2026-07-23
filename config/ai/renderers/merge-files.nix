{ lib }:

fileSets:
let
  rawPaths = lib.concatMap builtins.attrNames fileSets;
in
if builtins.length rawPaths == builtins.length (lib.unique rawPaths) then
  lib.foldl' (files: fileSet: files // fileSet) { } fileSets
else
  throw "nix-managed AI renderer contains duplicate target paths"
