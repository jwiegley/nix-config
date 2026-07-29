{
  derivationName =
    package:
    if (package ? name) && package.name != null then
      package.name
    else
      throw "Darwin surface package has no derivation name";

  homebrewName =
    kind: value:
    if builtins.isString value then
      value
    else if (value ? name) && value.name != null then
      value.name
    else
      throw "Darwin surface ${kind} entry is neither a string nor a named object";
}
