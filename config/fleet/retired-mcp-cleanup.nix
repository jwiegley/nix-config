{ lib, pkgs }:

{
  homeDirectory,
  retiredServers,
  retiredManifestMcpItems,
  retiredManifestSkillItems,
  codexRoots ? [ ],
  claudeRoots ? [ ],
  piRoots ? [ ],
  manifestRoots ? [ ],
}:

let
  unique = values: lib.sort builtins.lessThan (lib.unique values);
  validRelativePath =
    path:
    builtins.isString path
    && path != ""
    && !(lib.hasPrefix "/" path)
    && builtins.all (part: part != "" && part != "." && part != "..") (lib.splitString "/" path);
  roots = unique (codexRoots ++ claudeRoots ++ piRoots ++ manifestRoots);
  plan = {
    claudeRoots = unique claudeRoots;
    codexRoots = unique codexRoots;
    manifestRoots = unique manifestRoots;
    piRoots = unique piRoots;
    retiredManifestMcpItems = unique retiredManifestMcpItems;
    retiredManifestSkillItems = unique retiredManifestSkillItems;
    retiredServers = unique retiredServers;
  };
  planJson = builtins.toJSON plan;
  python = pkgs.python3.withPackages (packages: [
    packages.simplejson
    packages.tomlkit
  ]);
  program = pkgs.writeShellApplication {
    name = "nix-managed-retired-mcp-cleanup";
    text = ''
      exec ${python}/bin/python3 -I ${./retired-mcp-cleanup.py} "$@"
    '';
  };
  script = pkgs.writeShellScript "nix-managed-retired-mcp-cleanup-run" ''
    exec ${program}/bin/nix-managed-retired-mcp-cleanup \
      --home ${lib.escapeShellArg homeDirectory} \
      --plan-json ${lib.escapeShellArg planJson} \
      "$@"
  '';
in
assert builtins.isString homeDirectory && lib.hasPrefix "/" homeDirectory;
assert plan.retiredServers != [ ];
assert builtins.length plan.retiredServers == builtins.length retiredServers;
assert builtins.length plan.retiredManifestMcpItems == builtins.length retiredManifestMcpItems;
assert builtins.length plan.retiredManifestSkillItems == builtins.length retiredManifestSkillItems;
assert builtins.all (
  name: builtins.isString name && builtins.match "^[A-Za-z0-9][A-Za-z0-9_-]*$" name != null
) (plan.retiredServers ++ plan.retiredManifestMcpItems ++ plan.retiredManifestSkillItems);
assert builtins.all validRelativePath roots;
{
  inherit
    planJson
    program
    script
    ;
  activation = lib.hm.dag.entryAfter [ "linkGeneration" ] ''
    run ${script}
  '';
}
