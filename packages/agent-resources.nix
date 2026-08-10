{
  buildNpmPackage,
  buildPackages,
  callPackage,
  fetchzip,
  inputs,
  lib,
  python3,
  runCommand,
}:

let
  gitSurgeonSource = (callPackage "${inputs.llm-agents}/packages/git-surgeon/package.nix" { }).src;
  piSources = import ./source-catalog.nix "pi";

  ponytailSkills = [
    "ponytail"
    "ponytail-review"
    "ponytail-audit"
    "ponytail-debt"
    "ponytail-gain"
    "ponytail-help"
  ];

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

  wsSource = fetchzip piSources.ws.source.args;

  piMcpAdapter = buildNpmPackage {
    pname = "pi-mcp-adapter";
    version = piSources.pi-mcp-adapter.version;
    src = inputs.pi-mcp-adapter;
    patches = [ ./agent-resources/pi-mcp-adapter-xdg-config-home.patch ];
    npmDepsHash = piSources.pi-mcp-adapter.hashes.npmDepsHash;
    npmInstallFlags = [ "--omit=dev" ];
    dontNpmBuild = true;
    postPatch = ''
      # Nix validates every lock entry before npm applies --omit=dev. Remove
      # the unused development graph from both manifests instead of pinning
      # repairs for whichever dev-package versions upstream currently locks.
      ${python3}/bin/python3 - <<'PY'
      import json
      from pathlib import Path

      package_path = Path("package.json")
      package = json.loads(package_path.read_text())
      package.pop("devDependencies", None)
      package_path.write_text(json.dumps(package, indent=2) + "\n")

      lock_path = Path("package-lock.json")
      lock = json.loads(lock_path.read_text())
      lock["packages"][""].pop("devDependencies", None)
      lock["packages"] = {
          path: metadata
          for path, metadata in lock["packages"].items()
          if not metadata.get("dev", False)
      }
      lock_path.write_text(json.dumps(lock, indent=2) + "\n")
      PY
      ${python3}/bin/python3 ${./pi-mcp-adapter-normalize.py} init.ts
    '';
  };

in
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

  pi_openai_server_compaction="$extensions/pi-openai-server-compaction"
  mkdir "$pi_openai_server_compaction"
  mkdir "$pi_openai_server_compaction/src"
  mkdir -p "$pi_openai_server_compaction/node_modules/ws"
  ${copyPiOpenaiServerCompactionFiles}
  cp -- ${./agent-resources/pi-openai-server-compaction-active-history.ts} \
    "$pi_openai_server_compaction/src/active-history.ts"
  ${buildPackages.patch}/bin/patch --force --fuzz=0 --no-backup-if-mismatch \
    --directory="$pi_openai_server_compaction" --strip=1 \
    < ${./agent-resources/pi-openai-server-compaction-bounded-history.patch}
  cp -R -- ${lib.escapeShellArg "${wsSource}"}/. \
    "$pi_openai_server_compaction/node_modules/ws"/

  pi_quiet="$extensions/pi-quiet"
  mkdir "$pi_quiet"
  mkdir "$pi_quiet/src"
  ${copyPiQuietFiles}
  cp -- ${lib.escapeShellArg "${inputs.pi-quiet}/LICENSE"} "$pi_quiet/LICENSE"
  ${buildPackages.patch}/bin/patch --force --fuzz=0 --no-backup-if-mismatch \
    --directory="$pi_quiet" --strip=1 \
    < ${./agent-resources/pi-quiet-bounded-history.patch}

  pi_mcp="$extensions/pi-mcp-adapter"
  pi_mcp_source=${lib.escapeShellArg "${piMcpAdapter}/lib/node_modules/pi-mcp-adapter"}
  [ -d "$pi_mcp_source" ] && [ ! -L "$pi_mcp_source" ]
  [ ! -e "$pi_mcp" ] && [ ! -L "$pi_mcp" ]
  mkdir "$pi_mcp"
  cp -R -- "$pi_mcp_source"/. "$pi_mcp"/

''
