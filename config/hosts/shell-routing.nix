{ lib }:

let
  registry = import ./registry.nix;
  routingNames = builtins.attrNames registry.routing;
  validName = name: builtins.match "[a-z0-9][a-z0-9-]*" name != null;
  caseInsensitive =
    value:
    assert validName value;
    lib.concatMapStrings (
      character:
      let
        lower = lib.toLower character;
        upper = lib.toUpper character;
      in
      if lower == upper then character else "[${lower}${upper}]"
    ) (lib.stringToCharacters value);
  renderPatterns =
    class: route:
    map caseInsensitive ([ class ] ++ route.exactNames)
    ++ map (name: "*${caseInsensitive name}*") route.containsNames;
  renderNormalizeArm =
    class:
    let
      route = registry.routing.${class};
    in
    "    ${lib.concatStringsSep " | " (renderPatterns class route)}) printf '%s\\n' ${lib.escapeShellArg class} ;;";
  renderOutputArm =
    class:
    let
      route = registry.routing.${class};
    in
    "    ${lib.escapeShellArg class}) printf '%s\\n' ${lib.escapeShellArg route.flakeOutput} ;;";
  renderValues =
    values: lib.concatMapStrings (value: "    printf '%s\\n' ${lib.escapeShellArg value}\n") values;
in
assert builtins.all validName routingNames;
assert builtins.all (route: builtins.all validName (route.exactNames ++ route.containsNames)) (
  builtins.attrValues registry.routing
);
''
  #!/usr/bin/env bash
  # Generated from config/hosts/registry.nix by config/hosts/shell-routing.nix.
  # Edit the registry, not this projection.

  normalize_nix_host() {
      local host=''${1%%.*}
      case $host in
  ${lib.concatMapStringsSep "\n" renderNormalizeArm routingNames}
      *) return 1 ;;
      esac
  }

  nix_flake_output_for_host() {
      case $(normalize_nix_host "$1") in
  ${lib.concatMapStringsSep "\n" renderOutputArm routingNames}
      *) return 1 ;;
      esac
  }

  nix_shared_work_members() {
  ${renderValues registry.sharedWork.members}}

  nix_active_shared_work_rollout_hosts() {
  ${renderValues registry.sharedWork.activeRolloutMembers}}
''
