category:
let
  document = builtins.fromJSON (builtins.readFile (../sources + "/${category}.json"));
  validSource =
    source:
    builtins.isAttrs source
    &&
      builtins.attrNames source == [
        "args"
        "fetcher"
        "url"
      ]
    && builtins.isAttrs source.args
    && builtins.isString source.fetcher
    && builtins.isString source.url;
  validRecord =
    record:
    builtins.isAttrs record
    && record ? source
    && validSource record.source
    && record ? update
    && builtins.isAttrs record.update
    && (!record ? artifacts || builtins.isAttrs record.artifacts)
    && (!record ? hashes || builtins.isAttrs record.hashes);
in
assert
  builtins.attrNames document == [
    "schemaVersion"
    "sources"
  ];
assert document.schemaVersion == 1;
assert builtins.isAttrs document.sources;
assert builtins.all validRecord (builtins.attrValues document.sources);
document.sources
