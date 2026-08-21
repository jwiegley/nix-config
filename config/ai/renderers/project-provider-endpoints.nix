{ lib }:

{
  definitions,
  endpoints,
}:

let
  definitionNames = builtins.attrNames definitions;
  endpointNames = builtins.attrNames endpoints;
  # The catalog owns URL, credential-reference, and definition validation. This
  # helper only joins those validated authorities and groups the result by its
  # declared adapter owner.
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
lib.foldl' (
  byOwner: record:
  byOwner
  // {
    ${record.owner} = (byOwner.${record.owner} or [ ]) ++ [
      (builtins.removeAttrs record [ "owner" ])
    ];
  }
) { } records
