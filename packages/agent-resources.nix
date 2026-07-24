{
  buildNpmPackage,
  callPackage,
  fetchzip,
  inputs,
  lib,
  runCommand,
}:

let
  gitSurgeonSource = (callPackage "${inputs.llm-agents}/packages/git-surgeon/package.nix" { }).src;
  bigpowers = import ../config/ai/bigpowers-resources.nix;
  bigpowersSkills = builtins.attrNames (
    lib.filterAttrs (_name: type: type == "directory") (
      builtins.readDir "${inputs.bigpowers}/.pi/skills"
    )
  );
  bigpowersPrompts = map (lib.removeSuffix ".md") (
    builtins.attrNames (
      lib.filterAttrs (name: type: type == "regular" && lib.hasSuffix ".md" name) (
        builtins.readDir "${inputs.bigpowers}/.pi/prompts"
      )
    )
  );

  ponytailSkills = [
    "ponytail"
    "ponytail-review"
    "ponytail-audit"
    "ponytail-debt"
    "ponytail-gain"
    "ponytail-help"
  ];

  copyBigpowersSkills = lib.concatMapStringsSep "\n" (name: ''
    copy_skill ${lib.escapeShellArg "${inputs.bigpowers}/.pi/skills/${name}"} \
      ${lib.escapeShellArg name} ${lib.escapeShellArg "${inputs.bigpowers}/LICENSE"}
  '') bigpowers.names;

  copyBigpowersPrompts = lib.concatMapStringsSep "\n" (name: ''
    cp -- ${lib.escapeShellArg "${inputs.bigpowers}/.pi/prompts/${name}.md"} \
      "$prompts"/${lib.escapeShellArg "${name}.md"}
  '') bigpowers.names;

  copyPonytailSkills = lib.concatMapStringsSep "\n" (name: ''
    copy_skill ${lib.escapeShellArg "${inputs.ponytail}/skills/${name}"} \
      ${lib.escapeShellArg name}
  '') ponytailSkills;

  piQuietFiles = [
    "package.json"
    "CHANGELOG.md"
    "README.md"
    "src/classify.ts"
    "src/command.ts"
    "src/compaction.ts"
    "src/config.ts"
    "src/format.ts"
    "src/history.ts"
    "src/index.ts"
    "src/result-content.ts"
    "src/shell.ts"
    "src/tool-renderer-api.ts"
    "src/tools-meta.ts"
    "src/tools.ts"
  ];

  copyPiQuietFiles = lib.concatMapStringsSep "\n" (relative: ''
    cp -- ${lib.escapeShellArg "${inputs.pi-quiet}/packages/pi-quiet/${relative}"} \
      "$pi_quiet"/${lib.escapeShellArg relative}
  '') piQuietFiles;

  piOpenaiServerCompactionFiles = [
    "package.json"
    "LICENSE.md"
    "README.md"
    "src/config.ts"
    "src/custom-stream.ts"
    "src/index.ts"
    "src/openai-ws-connection.ts"
    "src/openai-ws-stream.ts"
    "src/openai.ts"
    "src/remote-compaction.ts"
    "src/state.ts"
    "src/stream-message-shared.ts"
  ];

  copyPiOpenaiServerCompactionFiles = lib.concatMapStringsSep "\n" (relative: ''
    cp -- ${lib.escapeShellArg "${inputs.pi-openai-server-compaction}/${relative}"} \
      "$pi_openai_server_compaction"/${lib.escapeShellArg relative}
  '') piOpenaiServerCompactionFiles;

  wsSource = fetchzip {
    url = "https://registry.npmjs.org/ws/-/ws-8.18.3.tgz";
    hash = "sha256-+o96RaViEX6JAoRI5JCLDJDcIXj+XbaH0+wSM9F2pBw=";
  };

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

in
assert bigpowersSkills == bigpowers.names;
assert bigpowersPrompts == bigpowers.names;
assert inputs.bigpowers.rev == bigpowers.revision;
assert inputs.bigpowers.narHash == bigpowers.narHash;
assert
  builtins.hashFile "sha256" "${inputs.bigpowers}/package.json"
  == "b95b2a687178b1d7314cc5cd66f6655269565b54abd139bc7b314c096aa3ddfb";
assert
  builtins.hashFile "sha256" "${inputs.bigpowers}/.pi/package.json"
  == "3546705df79cc06abfb92ca3f97b01592da4c30bb7d837db496551401c9979a2";
assert
  builtins.hashFile "sha256" "${inputs.bigpowers}/LICENSE"
  == "ab5c332485a9ffad649f5a341d5ecfd35abff52249bf2a5c958f168a002ce376";
assert
  builtins.hashFile "sha256" "${inputs.pi-mcp-adapter}/package-lock.json"
  == "156cd7b65090cb5600651b40563dea3974fbeeaa7dbb6346f3deb0e9e0528bd0";
assert
  builtins.hashFile "sha256" "${inputs.pi-openai-server-compaction}/package.json"
  == "f9cf0b5aaa73c1a3cf4ed92ba55c4c9f2784e46ef39c29822b279f3410452110";
assert
  builtins.hashFile "sha256" "${inputs.pi-quiet}/packages/pi-quiet/package.json"
  == "1b370c62fdf7b3b5a9fb35b45ba0cf0e3ceefa35e037f7cd9911b816ad03e4fa";
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

  ${copyBigpowersSkills}
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

  prompts="$out/share/agent-resources/prompts/bigpowers"
  mkdir -p "$prompts"
  ${copyBigpowersPrompts}

  extensions="$out/share/agent-resources/pi-extensions"
  mkdir "$extensions"

  pi_openai_server_compaction="$extensions/pi-openai-server-compaction"
  mkdir "$pi_openai_server_compaction"
  mkdir "$pi_openai_server_compaction/src"
  mkdir -p "$pi_openai_server_compaction/node_modules/ws"
  ${copyPiOpenaiServerCompactionFiles}
  cp -R -- ${lib.escapeShellArg "${wsSource}"}/. \
    "$pi_openai_server_compaction/node_modules/ws"/

  pi_quiet="$extensions/pi-quiet"
  mkdir "$pi_quiet"
  mkdir "$pi_quiet/src"
  ${copyPiQuietFiles}
  cp -- ${lib.escapeShellArg "${inputs.pi-quiet}/LICENSE"} "$pi_quiet/LICENSE"

  pi_mcp="$extensions/pi-mcp-adapter"
  pi_mcp_source=${lib.escapeShellArg "${piMcpAdapter}/lib/node_modules/pi-mcp-adapter"}
  [ -d "$pi_mcp_source" ] && [ ! -L "$pi_mcp_source" ]
  [ ! -e "$pi_mcp" ] && [ ! -L "$pi_mcp" ]
  mkdir "$pi_mcp"
  cp -R -- "$pi_mcp_source"/. "$pi_mcp"/

''
