def exact_keys($expected):
  type == "object" and ((keys | sort) == ($expected | sort));

def string_array:
  type == "array"
  and all(.[]; type == "string" and length > 0)
  and length == (unique | length);

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
    elif $contract.schemaVersion != 1 then
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
      "forbidDependencies"
    ]) | not) then
      error("invalid Pi npm common normalization policy")
    elif ($contract.common.removeTopLevel | string_array | not) or
         ($contract.common.forbidDependencies | string_array | not) then
      error("invalid Pi npm common normalization policy arrays")
    elif ($contract.targets | type) != "object" or
         ($contract.targets | length) == 0 or
         (all($contract.targets | keys[]; test("^[a-z0-9][a-z0-9-]*$")) | not) or
         (all($contract.targets[];
           exact_keys(["removeTopLevel", "forbidDependencies"])
           and (.removeTopLevel | string_array)
           and (.forbidDependencies | string_array)
         ) | not) then
      error("invalid Pi npm target normalization policies")
    elif ($contract.targets | has($target) | not) then
      error("unknown Pi npm normalization target: \($target)")
    else
      $contract.targets[$target] as $targetPolicy
      | ($contract.common.removeTopLevel + $targetPolicy.removeTopLevel) as $removed
      | ($contract.common.forbidDependencies + $targetPolicy.forbidDependencies) as $forbidden
      | if any($removed[]; . == "name" or . == "version" or
            . == "dependencies" or . == "optionalDependencies") then
          error("Pi npm normalization policy removes a protected manifest field")
        else
          reduce $removed[] as $field (.; del(.[$field]))
          | reduce $forbidden[] as $dependency (
              .;
              reduce dependency_sections[] as $section (
                .;
                del(.[$section][$dependency])
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
