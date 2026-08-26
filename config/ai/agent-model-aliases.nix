{
  lib,
  models ? import ./models.nix,
}:

# Add spoken names under the raw sets; Home Manager renders validated runtime JSON.

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
  normalizePairs =
    attrs:
    lib.mapAttrsToList (alias: target: {
      name = normalizeAlias alias;
      value = target;
    }) attrs;
  validModelTarget =
    target:
    builtins.isAttrs target
    &&
      builtins.attrNames target == [
        "harness"
        "model"
        "provider"
        "thinking"
      ]
    && target.harness == "pi"
    && builtins.isString target.provider
    && target.provider != ""
    && builtins.isString target.model
    && target.model != ""
    && builtins.elem target.thinking thinkingLevels;
  validMachineTarget =
    target:
    builtins.isAttrs target
    && builtins.attrNames target == [ "remote" ]
    && (target.remote == null || (builtins.isString target.remote && target.remote != ""));
  validProjectTarget =
    target:
    builtins.isAttrs target
    &&
      builtins.attrNames target == [
        "machine"
        "path"
      ]
    && builtins.isString target.machine
    && builtins.hasAttr target.machine machines
    && builtins.isString target.path
    && lib.hasPrefix "~/" target.path
    && builtins.all (part: part != "" && part != "." && part != "..") (lib.splitString "/" target.path);

  defaultAlias = "gpt sol";
  rawAliases = {
    deepseek = {
      harness = "pi";
      provider = "omlx-hera";
      model = models.omlx.reasoning.name;
      thinking = "max";
    };
    "gpt sol" = {
      harness = "pi";
      provider = "openai-codex";
      model = models.codex.name;
      thinking = "max";
    };
  };
  defaultMachine = "hera";
  rawMachines = {
    hera.remote = null;
    "andoria-08".remote = "andoria-08";
  };
  rawProjects = {
    nix = {
      machine = "hera";
      path = "~/src/nix";
    };
    ares = {
      machine = "hera";
      path = "~/hera/ares/main";
    };
    agent-cat = {
      machine = "hera";
      path = "~/src/agent-cat";
    };
    tron = {
      machine = "andoria-08";
      path = "~/tron/main";
    };
  };

  modelPairs = normalizePairs rawAliases;
  machinePairs = normalizePairs rawMachines;
  projectPairs = normalizePairs rawProjects;
  aliases = builtins.listToAttrs modelPairs;
  machines = builtins.listToAttrs machinePairs;
  projects = builtins.listToAttrs projectPairs;
  normalizedDefault = normalizeAlias defaultAlias;
  normalizedDefaultMachine = normalizeAlias defaultMachine;
  aliasesAreNormalized =
    values:
    builtins.all (alias: alias != "" && alias == normalizeAlias alias) (builtins.attrNames values);
in
assert builtins.length modelPairs == builtins.length (builtins.attrNames aliases);
assert builtins.length machinePairs == builtins.length (builtins.attrNames machines);
assert builtins.length projectPairs == builtins.length (builtins.attrNames projects);
assert aliasesAreNormalized aliases;
assert aliasesAreNormalized machines;
assert aliasesAreNormalized projects;
assert builtins.all validModelTarget (builtins.attrValues aliases);
assert builtins.all validMachineTarget (builtins.attrValues machines);
assert builtins.all validProjectTarget (builtins.attrValues projects);
assert builtins.hasAttr normalizedDefault aliases;
assert builtins.hasAttr normalizedDefaultMachine machines;
{
  version = 1;
  defaultAlias = normalizedDefault;
  defaultMachine = normalizedDefaultMachine;
  inherit aliases machines projects;
}
