category:
let
  document = builtins.fromJSON (builtins.readFile (../sources + "/${category}.json"));
in
assert document.schemaVersion == 1;
document.sources
