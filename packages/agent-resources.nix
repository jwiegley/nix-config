{
  buildNpmPackage,
  inputs,
  lib,
  runCommand,
  stdenv,
}:

let
  system = stdenv.hostPlatform.system;
  gitSurgeonSource = inputs.llm-agents.packages.${system}.git-surgeon.src;

  superpowersSkills = builtins.attrNames (
    lib.filterAttrs (_name: type: type == "directory") (builtins.readDir "${inputs.superpowers}/skills")
  );

  ponytailSkills = [
    "ponytail"
    "ponytail-review"
    "ponytail-audit"
    "ponytail-debt"
    "ponytail-gain"
    "ponytail-help"
  ];

  copySuperpowersSkills = lib.concatMapStringsSep "\n" (name: ''
    copy_skill ${lib.escapeShellArg "${inputs.superpowers}/skills/${name}"} \
      ${lib.escapeShellArg name} ${lib.escapeShellArg "${inputs.superpowers}/LICENSE"}
  '') superpowersSkills;

  copyPonytailSkills = lib.concatMapStringsSep "\n" (name: ''
    copy_skill ${lib.escapeShellArg "${inputs.ponytail}/skills/${name}"} \
      ${lib.escapeShellArg name}
  '') ponytailSkills;

  piMcpAdapter = buildNpmPackage {
    pname = "pi-mcp-adapter";
    version = "2.11.0";
    src = inputs.pi-mcp-adapter;
    npmDepsHash = "sha256-xIW2WTuVj6SeFGrJPEduzzVCT548i7tzlP5sq3ky/wI=";
    npmInstallFlags = [ "--omit=dev" ];
    dontNpmBuild = true;
    postPatch = ''
      # The pinned upstream lock omits integrity on three dev-only nested
      # packages. Nix parses the whole lock before npm applies --omit=dev.
      substituteInPlace package-lock.json \
        --replace-fail \
          '"resolved": "https://registry.npmjs.org/@earendil-works/pi-agent-core/-/pi-agent-core-0.79.10.tgz",' \
          $'"resolved": "https://registry.npmjs.org/@earendil-works/pi-agent-core/-/pi-agent-core-0.79.10.tgz",\n      "integrity": "sha512-XKxgdjhcPuyjrthCOFSgfzT3xZ1uBrJ1IMVDxci1to6hIN6BIg9J5iY8q0pGXK1DLgATLP23da+1UyZLwA360Q==",' \
        --replace-fail \
          '"resolved": "https://registry.npmjs.org/@earendil-works/pi-ai/-/pi-ai-0.79.10.tgz",' \
          $'"resolved": "https://registry.npmjs.org/@earendil-works/pi-ai/-/pi-ai-0.79.10.tgz",\n      "integrity": "sha512-9jR23tOl0BIUdQMn70Gr72xYBpM7Xgl9Lyv7gAnU1USfkNRuYG/f/edLl+n/Dp/RafDW3JI4DF7y/GhgkORuew==",' \
        --replace-fail \
          '"resolved": "https://registry.npmjs.org/@earendil-works/pi-tui/-/pi-tui-0.79.10.tgz",' \
          $'"resolved": "https://registry.npmjs.org/@earendil-works/pi-tui/-/pi-tui-0.79.10.tgz",\n      "integrity": "sha512-FUVOjDn1DVwM1uHD5MNYboXQrXjIDbSt+BQ3py7nQWCY62tKfxgiM1OBMxTcwRWLfSdZHUPpV0hm1loIdUJnPw==",'
    '';
  };

  piSubagentFiles = [
    "package.json"
    "index.ts"
    "agents.ts"
    "contract.ts"
    "output.ts"
    "runner.ts"
    "runner-cli.js"
    "runner-events.js"
    "session-lock.ts"
    "session-paths.ts"
    "render.ts"
    "types.ts"
    "README.md"
    "LICENSE"
  ];

  copyPiSubagentFiles = lib.concatMapStringsSep "\n" (relative: ''
    cp -- ${lib.escapeShellArg "${inputs.pi-subagent}/${relative}"} \
      "$pi_subagent"/${lib.escapeShellArg relative}
  '') piSubagentFiles;
in
assert
  builtins.hashFile "sha256" "${inputs.pi-mcp-adapter}/package-lock.json"
  == "156cd7b65090cb5600651b40563dea3974fbeeaa7dbb6346f3deb0e9e0528bd0";
assert
  builtins.hashFile "sha256" "${inputs.pi-subagent}/package-lock.json"
  == "a7fbb2c6c10ee6af111dcf7a10064770cc360e818b6f424854c231ed6872d5ff";
runCommand "agent-resources" { } ''
  set -euo pipefail

  skills="$out/share/agent-resources/skills"
  mkdir -p "$skills"

  copy_skill() {
    source_tree=$1
    name=$2
    license=''${3:-}
    destination="$skills/$name"

    [ -d "$source_tree" ] && [ ! -L "$source_tree" ]
    [ ! -e "$destination" ] && [ ! -L "$destination" ]
    mkdir "$destination"
    cp -R -- "$source_tree"/. "$destination"/

    if [ -n "$license" ]; then
      [ -f "$license" ] && [ ! -L "$license" ]
      [ ! -e "$destination/LICENSE" ] && [ ! -L "$destination/LICENSE" ]
      cp -- "$license" "$destination/LICENSE"
    fi
  }

  ${copySuperpowersSkills}
  ${copyPonytailSkills}
  copy_skill ${lib.escapeShellArg "${gitSurgeonSource}/skills/git-surgeon"} \
    git-surgeon ${lib.escapeShellArg "${gitSurgeonSource}/LICENSE"}

  translate="$skills/translate-en"
  [ ! -e "$translate" ] && [ ! -L "$translate" ]
  mkdir "$translate"
  cp -- ${lib.escapeShellArg "${inputs.translate-tool}/skill/SKILL.md"} \
    "$translate/SKILL.md"
  cp -- ${lib.escapeShellArg "${inputs.translate-tool}/glossary.csv"} \
    "$translate/GLOSSARY.csv"

  extensions="$out/share/agent-resources/pi-extensions"
  mkdir "$extensions"

  pi_mcp="$extensions/pi-mcp-adapter"
  pi_mcp_source=${lib.escapeShellArg "${piMcpAdapter}/lib/node_modules/pi-mcp-adapter"}
  [ -d "$pi_mcp_source" ] && [ ! -L "$pi_mcp_source" ]
  [ ! -e "$pi_mcp" ] && [ ! -L "$pi_mcp" ]
  mkdir "$pi_mcp"
  cp -R -- "$pi_mcp_source"/. "$pi_mcp"/

  pi_subagent="$extensions/pi-subagent"
  [ ! -e "$pi_subagent" ] && [ ! -L "$pi_subagent" ]
  mkdir "$pi_subagent"
  mkdir "$pi_subagent/agents"
  ${copyPiSubagentFiles}
  cp -- ${lib.escapeShellArg "${inputs.pi-subagent}/agents/oracle.md"} \
    "$pi_subagent/agents/oracle.md"
''
