{ lib }:

{
  definitions,
  endpoints,
}:

let
  definitionNames = builtins.attrNames definitions;
  endpointNames = builtins.attrNames endpoints;
  validApiKey =
    value:
    builtins.isAttrs value
    && builtins.attrNames value == [ "env" ]
    && builtins.isString value.env
    && value.env != "";
  validDefinition =
    value:
    builtins.isAttrs value
    && builtins.all (
      name:
      builtins.elem name [
        "apiKey"
        "name"
        "owner"
      ]
    ) (builtins.attrNames value)
    && builtins.isString (value.owner or null)
    && value.owner != ""
    && builtins.isString (value.name or null)
    && value.name != ""
    && (!(value ? apiKey) || validApiKey value.apiKey);
  validEndpoint =
    value:
    (builtins.isString value && value != "")
    || (
      builtins.isAttrs value
      && builtins.all (
        name:
        builtins.elem name [
          "apiKey"
          "baseUrl"
        ]
      ) (builtins.attrNames value)
      && builtins.isString (value.baseUrl or null)
      && value.baseUrl != ""
      && (!(value ? apiKey) || validApiKey value.apiKey)
    );
  records = map (
    id:
    let
      definition = definitions.${id};
      endpoint = endpoints.${id};
      endpointApiKey = if builtins.isAttrs endpoint then endpoint.apiKey or null else null;
      definitionApiKey = definition.apiKey or null;
      apiKey = if endpointApiKey != null then endpointApiKey else definitionApiKey;
    in
    assert lib.assertMsg (
      endpointApiKey == null || definitionApiKey == null
    ) "provider ${id} has more than one credential-reference authority";
    {
      inherit id;
      inherit (definition) name owner;
      baseUrl = if builtins.isString endpoint then endpoint else endpoint.baseUrl;
    }
    // lib.optionalAttrs (apiKey != null) { inherit apiKey; }
  ) definitionNames;
in
assert lib.assertMsg (definitionNames == endpointNames) "provider definitions and endpoints differ";
assert lib.assertMsg (builtins.all (
  name: validDefinition definitions.${name}
) definitionNames) "invalid provider definition";
assert lib.assertMsg (builtins.all (
  name: validEndpoint endpoints.${name}
) endpointNames) "invalid provider endpoint";
lib.foldl' (
  byOwner: record:
  byOwner
  // {
    ${record.owner} = (byOwner.${record.owner} or [ ]) ++ [
      (builtins.removeAttrs record [ "owner" ])
    ];
  }
) { } records
