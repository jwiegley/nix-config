def exact_keys($expected):
  type == "object" and ((keys | sort) == ($expected | sort));

def string_array:
  type == "array"
  and all(.[]; type == "string" and length > 0)
  and length == (unique | length);

def string_object:
  type == "object"
  and all(to_entries[]; (.key | length > 0) and (.value | type == "string" and length > 0));

def dependency_sections:
  ["dependencies", "optionalDependencies", "peerDependencies", "devDependencies"];

if type != "object" then
  error("Pi npm manifest must be a JSON object")
elif (.name | type) != "string" or (.version | type) != "string" then
  error("Pi npm manifest must declare string name and version fields")
elif .name != $expectedName or .version != $expectedVersion then
  error("Pi npm manifest identity does not match the catalog target")
elif ($policy | length) != 1 or ($policy[0] | type) != "object" then
  error("Pi npm normalization contract must contain one JSON object")
else
  $policy[0] as $contract
  | if ($contract | exact_keys([
      "schemaVersion",
      "npmDependencyFlags",
      "common",
      "targets"
    ]) | not) then
      error("invalid Pi npm normalization contract fields")
    elif $contract.schemaVersion != 3 then
      error("unsupported Pi npm normalization contract schema")
    elif $contract.npmDependencyFlags != [
      "--ignore-scripts",
      "--omit=dev",
      "--omit=peer",
      "--legacy-peer-deps"
    ] then
      error("invalid Pi npm dependency flags")
    elif ($contract.common | exact_keys([
      "removeTopLevel",
      "forbidDependencies",
      "defensiveForbidDependencies",
      "overrideDependencies"
    ]) | not) then
      error("invalid Pi npm common normalization policy")
    elif ($contract.common.removeTopLevel | string_array | not) or
         ($contract.common.forbidDependencies | string_array | not) or
         ($contract.common.defensiveForbidDependencies | string_array | not) or
         ($contract.common.overrideDependencies | string_object | not) or
         (($contract.common.forbidDependencies +
           $contract.common.defensiveForbidDependencies) | length != (unique | length)) then
      error("invalid Pi npm common normalization policy arrays")
    elif ($contract.targets | type) != "object" or
         ($contract.targets | length) == 0 or
         (all($contract.targets | keys[]; test("^[a-z0-9][a-z0-9-]*$")) | not) or
         (all($contract.targets[];
           exact_keys([
             "removeTopLevel",
             "forbidDependencies",
             "defensiveForbidDependencies",
             "overrideDependencies"
           ])
           and (.removeTopLevel | string_array)
           and (.forbidDependencies | string_array)
           and (.defensiveForbidDependencies | string_array)
           and (.overrideDependencies | string_object)
           and ((.forbidDependencies + .defensiveForbidDependencies) |
             length == (unique | length))
         ) | not) then
      error("invalid Pi npm target normalization policies")
    elif ($contract.targets | has($target) | not) then
      error("unknown Pi npm normalization target: \($target)")
    else
      $contract.targets[$target] as $targetPolicy
      | ($contract.common.removeTopLevel + $targetPolicy.removeTopLevel) as $removed
      | ($contract.common.forbidDependencies +
         $targetPolicy.forbidDependencies) as $enforced
      | ($contract.common.defensiveForbidDependencies +
         $targetPolicy.defensiveForbidDependencies) as $defensive
      | ($enforced + $defensive) as $forbidden
      | (($contract.common.overrideDependencies | keys) +
         ($targetPolicy.overrideDependencies | keys)) as $overrideNames
      | ($contract.common.overrideDependencies +
         $targetPolicy.overrideDependencies) as $overrides
      | if ($forbidden | length) != ($forbidden | unique | length) then
          error("Pi npm dependency repeats across combined normalization policies")
        elif ($overrideNames | length) != ($overrideNames | unique | length) then
          error("Pi npm dependency repeats across combined override policies")
        elif any($overrideNames[]; . as $dependency | $forbidden | index($dependency) != null) then
          error("Pi npm dependency repeats across override and forbidden policies")
        elif any($removed[]; . == "name" or . == "version" or
            . == "dependencies" or . == "optionalDependencies") then
          error("Pi npm normalization policy removes a protected manifest field")
        else
          . as $manifest
          | [
              $enforced[] as $dependency
              | select(any(dependency_sections[];
                  . as $section
                  | (($manifest[$section] // {}) | has($dependency))) | not)
              | $dependency
            ] as $inert
          | [
              $overrideNames[] as $dependency
              | select(any(["dependencies", "optionalDependencies"][];
                  . as $section
                  | (($manifest[$section] // {}) | has($dependency))) | not)
              | $dependency
            ] as $inertOverrides
          | if ($inert | length) > 0 then
              error("inert enforced Pi npm dependencies: \($inert | join(", "))")
            elif ($inertOverrides | length) > 0 then
              error("inert Pi npm dependency overrides: \($inertOverrides | join(", "))")
            else
              reduce $removed[] as $field ($manifest; del(.[$field]))
              | reduce $forbidden[] as $dependency (
                .;
                reduce dependency_sections[] as $section (
                  .;
                  del(.[$section][$dependency])
                )
              )
              | reduce ($overrides | to_entries[]) as $override (
                  .;
                  reduce ["dependencies", "optionalDependencies"][] as $section (
                    .;
                    if ((.[$section] // {}) | has($override.key)) then
                      .[$section][$override.key] = $override.value
                    else
                      .
                    end
                  )
                )
              | . as $normalized
              | if any($forbidden[];
                  . as $dependency
                  | any(dependency_sections[];
                      . as $section
                      | (($normalized[$section] // {}) | has($dependency)))) then
                  error("forbidden Pi npm dependency survived normalization")
                else
                  .
                end
            end
        end
    end
end
