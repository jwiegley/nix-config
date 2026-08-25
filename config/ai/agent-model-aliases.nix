{ lib }:

# Add spoken names under rawAliases; Home Manager renders the validated runtime JSON.

let
  thinkingLevels = [
    "off"
    "minimal"
    "low"
    "medium"
    "high"
    "xhigh"
    "max"
  ];
  normalizeAlias =
    alias:
    lib.concatStringsSep " " (lib.filter (part: part != "") (lib.splitString " " (lib.toLower alias)));
  targetKeys = [
    "harness"
    "model"
    "provider"
    "thinking"
  ];
  validTarget =
    target:
    builtins.isAttrs target
    && builtins.attrNames target == targetKeys
    && target.harness == "pi"
    && builtins.isString target.provider
    && target.provider != ""
    && builtins.isString target.model
    && target.model != ""
    && builtins.elem target.thinking thinkingLevels;

  defaultAlias = "gpt sol";
  rawAliases = {
    deepseek = {
      harness = "pi";
      provider = "omlx-hera";
      model = "DeepSeek-V4-Flash-0731-oQ8e-mtp";
      thinking = "off";
    };
    "gpt sol" = {
      harness = "pi";
      provider = "openai-codex";
      model = "gpt-5.6-sol";
      thinking = "max";
    };
  };
  normalizedPairs = lib.mapAttrsToList (alias: target: {
    name = normalizeAlias alias;
    value = target;
  }) rawAliases;
  aliases = builtins.listToAttrs normalizedPairs;
  normalizedDefault = normalizeAlias defaultAlias;
in
assert builtins.length normalizedPairs == builtins.length (builtins.attrNames aliases);
assert builtins.all (alias: alias != "" && alias == normalizeAlias alias) (
  builtins.attrNames aliases
);
assert builtins.all validTarget (builtins.attrValues aliases);
assert builtins.hasAttr normalizedDefault aliases;
{
  version = 1;
  defaultAlias = normalizedDefault;
  inherit aliases;
}
