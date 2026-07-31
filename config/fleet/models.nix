{
  registryFile ? ./model-registry.json,
  registry ? builtins.fromJSON (builtins.readFile registryFile),
  policy ? import ./model-policy.nix,
}:

let
  sortStrings = builtins.sort builtins.lessThan;
  exactKeys =
    expected: value: builtins.isAttrs value && builtins.attrNames value == sortStrings expected;
  allowedKeys =
    allowed: value:
    builtins.isAttrs value && builtins.all (key: builtins.elem key allowed) (builtins.attrNames value);
  hasKeys = keys: value: builtins.all (key: builtins.hasAttr key value) keys;
  nonEmptyString = value: builtins.isString value && builtins.stringLength value > 0;
  uniqueStrings =
    values:
    builtins.length values == builtins.length (
      builtins.attrNames (
        builtins.listToAttrs (
          map (value: {
            name = value;
            value = true;
          }) values
        )
      )
    );
  validStringList =
    values: builtins.isList values && builtins.all nonEmptyString values && uniqueStrings values;
  validNonEmptyStringList = values: validStringList values && builtins.length values > 0;
  ensure = condition: message: if condition then true else throw "model registry: ${message}";

  policyTopKeys = [
    "allowedHosts"
    "allowedInsecureBaseUrlsByProvider"
    "allowedNonSecretCredentialsByProvider"
    "profileDefaultProfiles"
    "providers"
    "syncChatPath"
  ];
  allowedHosts =
    if policy ? allowedHosts && builtins.isList policy.allowedHosts then policy.allowedHosts else [ ];
  allowedInsecureBaseUrlsByProvider =
    if
      policy ? allowedInsecureBaseUrlsByProvider
      && builtins.isAttrs policy.allowedInsecureBaseUrlsByProvider
    then
      policy.allowedInsecureBaseUrlsByProvider
    else
      { };
  allowedNonSecretCredentialsByProvider =
    if
      policy ? allowedNonSecretCredentialsByProvider
      && builtins.isAttrs policy.allowedNonSecretCredentialsByProvider
    then
      policy.allowedNonSecretCredentialsByProvider
    else
      { };

  validSelectors =
    value:
    allowedKeys [
      "clients"
      "excludeProfiles"
    ] value
    && builtins.all (key: !builtins.hasAttr key value || validNonEmptyStringList value.${key}) [
      "clients"
      "excludeProfiles"
    ];
  validDroid =
    value:
    allowedKeys [
      "extraArgs"
      "extraHeaders"
      "noImageSupport"
      "providerType"
    ] value
    && value ? providerType
    && nonEmptyString value.providerType
    && (!value ? noImageSupport || builtins.isBool value.noImageSupport)
    && (
      !value ? extraArgs
      || (
        builtins.isAttrs value.extraArgs
        && builtins.all (
          key:
          let
            item = value.extraArgs.${key};
          in
          builtins.isBool item || builtins.isInt item || builtins.isFloat item || builtins.isString item
        ) (builtins.attrNames value.extraArgs)
      )
    )
    && (
      !value ? extraHeaders
      || (
        builtins.isAttrs value.extraHeaders
        && builtins.all (key: nonEmptyString value.extraHeaders.${key}) (
          builtins.attrNames value.extraHeaders
        )
      )
    );
  validOpenCode =
    value:
    exactKeys [
      "name"
      "npm"
      "timeout"
    ] value
    && hasKeys [
      "name"
      "npm"
      "timeout"
    ] value
    && nonEmptyString value.name
    && nonEmptyString value.npm
    && builtins.isBool value.timeout;
  validProviderPolicy =
    value:
    allowedKeys [
      "droid"
      "opencode"
      "selectors"
    ] value
    && hasKeys [
      "droid"
      "selectors"
    ] value
    && validSelectors value.selectors
    && validDroid value.droid
    && (!value ? opencode || validOpenCode value.opencode);
  validSyncPath =
    value:
    nonEmptyString value
    && builtins.match "[A-Za-z0-9._~/-]+" value != null
    && builtins.substring 0 1 value != "/"
    && builtins.match ".*[.][.].*" value == null;

  rawProviders =
    if registry ? providers && builtins.isList registry.providers then registry.providers else [ ];
  rawModels = if registry ? models && builtins.isList registry.models then registry.models else [ ];
  rawSelections =
    if registry ? selections && builtins.isAttrs registry.selections then registry.selections else { };

  providerRequiredKeys = [
    "apiKey"
    "baseUrl"
    "displayName"
    "id"
  ];
  providerAllowedKeys = providerRequiredKeys ++ [ "hosts" ];
  modelRequiredKeys = [
    "displayName"
    "id"
    "maxOutputTokens"
    "provider"
  ];
  modelAllowedKeys = modelRequiredKeys ++ [
    "contextLimit"
    "hosts"
    "outputLimit"
  ];
  selectionRoles = [
    "default"
    "claudeDefault"
    "claudeHaiku"
    "claudeSubagent"
  ];

  validProviderId =
    value: nonEmptyString value && builtins.match "[A-Za-z0-9][A-Za-z0-9._-]*" value != null;
  validHosts =
    value: validNonEmptyStringList value && builtins.all (host: builtins.elem host allowedHosts) value;
  validCredential =
    providerId: value:
    builtins.isAttrs value
    && (
      (
        builtins.attrNames value == [ "env" ]
        && nonEmptyString value.env
        && builtins.match "[A-Z][A-Z0-9_]*" value.env != null
      )
      || (
        builtins.attrNames value == [ "nonSecret" ]
        && nonEmptyString value.nonSecret
        && builtins.hasAttr providerId allowedNonSecretCredentialsByProvider
        && value.nonSecret == allowedNonSecretCredentialsByProvider.${providerId}
      )
    );
  validBaseUrl =
    providerId: value:
    nonEmptyString value
    && (
      (
        builtins.hasAttr providerId allowedInsecureBaseUrlsByProvider
        && value == allowedInsecureBaseUrlsByProvider.${providerId}
      )
      || builtins.match "https://[^/?#[:space:]@]+(/[^?#[:space:]]*)?" value != null
    )
    && builtins.match ".*[$].*" value == null
    && builtins.match ".*[{]env:.*" value == null;
  validProvider =
    value:
    allowedKeys providerAllowedKeys value
    && hasKeys providerRequiredKeys value
    && validProviderId value.id
    && nonEmptyString value.displayName
    && validBaseUrl value.id value.baseUrl
    && validCredential value.id value.apiKey
    && (!value ? hosts || validHosts value.hosts);
  validPositiveInt = value: builtins.isInt value && value > 0;
  validModel =
    value:
    allowedKeys modelAllowedKeys value
    && hasKeys modelRequiredKeys value
    && nonEmptyString value.provider
    && nonEmptyString value.id
    && nonEmptyString value.displayName
    && validPositiveInt value.maxOutputTokens
    && (!value ? contextLimit || validPositiveInt value.contextLimit)
    && (!value ? outputLimit || validPositiveInt value.outputLimit)
    && (!value ? hosts || validHosts value.hosts);
  validSelection =
    value:
    exactKeys [
      "model"
      "provider"
    ] value
    && hasKeys [
      "model"
      "provider"
    ] value
    && nonEmptyString value.provider
    && nonEmptyString value.model;

  providerIds = map (
    value: if builtins.isAttrs value && value ? id && builtins.isString value.id then value.id else ""
  ) rawProviders;
  modelPairs = map (
    value:
    if
      builtins.isAttrs value
      && value ? provider
      && builtins.isString value.provider
      && value ? id
      && builtins.isString value.id
    then
      builtins.toJSON [
        value.provider
        value.id
      ]
    else
      ""
  ) rawModels;
  compositeModelKeys = map (
    value:
    if
      builtins.isAttrs value
      && value ? provider
      && builtins.isString value.provider
      && value ? id
      && builtins.isString value.id
    then
      "${value.provider}/${value.id}"
    else
      ""
  ) rawModels;

  selectionChecks =
    if exactKeys selectionRoles rawSelections then
      map (role: ensure (validSelection rawSelections.${role}) "invalid selection ${role}") selectionRoles
    else
      [ (ensure false "selection roles differ from the schema") ];
  selectionReferenceChecks =
    if builtins.all validSelection (builtins.attrValues rawSelections) then
      map (
        role:
        let
          selection = rawSelections.${role};
        in
        ensure (
          builtins.elem selection.provider providerIds
          && builtins.elem (builtins.toJSON [
            selection.provider
            selection.model
          ]) modelPairs
        ) "selection ${role} does not resolve"
      ) selectionRoles
    else
      [ ];

  providerPolicyNames =
    if policy ? providers && builtins.isAttrs policy.providers then
      builtins.attrNames policy.providers
    else
      [ ];
  validProviderStringMap =
    value:
    builtins.isAttrs value
    && builtins.length (builtins.attrNames value) > 0
    && builtins.all (name: builtins.elem name providerIds && nonEmptyString value.${name}) (
      builtins.attrNames value
    );
  policyChecks = [
    (ensure (exactKeys policyTopKeys policy) "policy keys differ from the schema")
    (ensure (validNonEmptyStringList allowedHosts) "invalid policy host allowlist")
    (ensure (validProviderStringMap allowedNonSecretCredentialsByProvider) "invalid provider-bound nonsecret credential allowlist")
    (ensure (
      validProviderStringMap allowedInsecureBaseUrlsByProvider
      && builtins.all (
        name:
        builtins.match "http://[^/?#[:space:]@]+(/[^?#[:space:]]*)?"
          allowedInsecureBaseUrlsByProvider.${name} != null
      ) (builtins.attrNames allowedInsecureBaseUrlsByProvider)
    ) "invalid provider-bound insecure URL allowlist")
    (ensure (
      policy ? profileDefaultProfiles && validNonEmptyStringList policy.profileDefaultProfiles
    ) "invalid profile default fan-out")
    (ensure (policy ? syncChatPath && validSyncPath policy.syncChatPath) "invalid sync chat path")
    (ensure (policy ? providers && builtins.isAttrs policy.providers) "invalid provider policy set")
    (ensure (sortStrings providerPolicyNames == sortStrings providerIds) "provider policy set differs")
  ]
  ++ (
    if policy ? providers && builtins.isAttrs policy.providers then
      map (
        name: ensure (validProviderPolicy policy.providers.${name}) "invalid provider policy ${name}"
      ) providerPolicyNames
    else
      [ ]
  );

  registryChecks = [
    (ensure (exactKeys [
      "models"
      "providers"
      "schemaVersion"
      "selections"
    ] registry) "top-level keys differ from schema")
    (ensure (registry ? schemaVersion && registry.schemaVersion == 2) "unsupported schema version")
    (ensure (registry ? providers && builtins.isList registry.providers) "providers must be an array")
    (ensure (registry ? models && builtins.isList registry.models) "models must be an array")
    (ensure (
      registry ? selections && builtins.isAttrs registry.selections
    ) "selections must be an object")
    (ensure (
      builtins.length providerIds == builtins.length (
        builtins.attrNames (
          builtins.listToAttrs (
            map (id: {
              name = id;
              value = true;
            }) providerIds
          )
        )
      )
    ) "provider IDs are not unique")
    (ensure (
      builtins.length modelPairs == builtins.length (
        builtins.attrNames (
          builtins.listToAttrs (
            map (pair: {
              name = pair;
              value = true;
            }) modelPairs
          )
        )
      )
    ) "model routes are not unique")
    (ensure (
      builtins.length compositeModelKeys == builtins.length (
        builtins.attrNames (
          builtins.listToAttrs (
            map (key: {
              name = key;
              value = true;
            }) compositeModelKeys
          )
        )
      )
    ) "composite model keys are not unique")
  ]
  ++ builtins.genList (
    index:
    ensure (validProvider (builtins.elemAt rawProviders index)) "invalid provider at index ${toString index}"
  ) (builtins.length rawProviders)
  ++ builtins.genList (
    index:
    let
      model = builtins.elemAt rawModels index;
    in
    ensure (
      validModel model && builtins.elem model.provider providerIds
    ) "invalid model at index ${toString index}"
  ) (builtins.length rawModels)
  ++ selectionChecks
  ++ selectionReferenceChecks;

  validated = builtins.deepSeq (policyChecks ++ registryChecks) true;

  providers = builtins.listToAttrs (
    builtins.genList (
      index:
      let
        source = builtins.elemAt rawProviders index;
        providerPolicy = policy.providers.${source.id};
      in
      {
        name = source.id;
        value = {
          inherit (source) apiKey baseUrl displayName;
          sourceOrder = index;
          selectors =
            providerPolicy.selectors // (if source ? hosts then { inherit (source) hosts; } else { });
        }
        // (if providerPolicy ? droid then { inherit (providerPolicy) droid; } else { })
        // (if providerPolicy ? opencode then { inherit (providerPolicy) opencode; } else { });
      }
    ) (builtins.length rawProviders)
  );

  models = builtins.listToAttrs (
    builtins.genList (
      index:
      let
        source = builtins.elemAt rawModels index;
      in
      {
        name = "${source.provider}/${source.id}";
        value = {
          inherit (source)
            displayName
            id
            maxOutputTokens
            provider
            ;
          sourceOrder = index;
          selectors = if source ? hosts then { inherit (source) hosts; } else { };
        }
        // (if source ? contextLimit then { inherit (source) contextLimit; } else { })
        // (if source ? outputLimit then { inherit (source) outputLimit; } else { });
      }
    ) (builtins.length rawModels)
  );

  selections = rawSelections;
  profileDefaults = builtins.listToAttrs (
    map (profileId: {
      name = profileId;
      value = selections.default;
    }) policy.profileDefaultProfiles
  );
  selectedProvider = providers.${selections.default.provider};
  selectedBaseUrlLength = builtins.stringLength selectedProvider.baseUrl;
  selectedBaseUrl =
    if
      selectedBaseUrlLength > 0
      && builtins.substring (selectedBaseUrlLength - 1) 1 selectedProvider.baseUrl == "/"
    then
      builtins.substring 0 (selectedBaseUrlLength - 1) selectedProvider.baseUrl
    else
      selectedProvider.baseUrl;
  syncInputs = selections.default // {
    chatUrl = "${selectedBaseUrl}/${policy.syncChatPath}";
  };
in
assert validated;
{
  inherit
    models
    profileDefaults
    providers
    selections
    syncInputs
    ;
}
