{
  buildPackages,
  callPackage,
  fetchzip,
  inputs,
  lib,
  python3,
  runCommand,
  stdenv,
}:

let
  gitSurgeonSource = (callPackage "${inputs.llm-agents}/packages/git-surgeon/package.nix" { }).src;
  piSources = import ./source-catalog.nix "pi";
  skillCreatorPython = python3.withPackages (pythonPackages: [ pythonPackages.pyyaml ]);
  skillCreatorScripts = [
    "init_skill.py"
    "package_skill.py"
    "quick_validate.py"
  ];
  skillCreatorScriptArgs = lib.escapeShellArgs skillCreatorScripts;

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
    "src/bash-settings.ts"
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

  piMcpForbiddenBuildScripts = [
    "predependencies"
    "dependencies"
    "postdependencies"
    "preinstall"
    "install"
    "postinstall"
    "prepublish"
    "prepublishOnly"
    "preprepare"
    "prepare"
    "postprepare"
    "postpack"
    "publish"
    "postpublish"
    "prebuild:public"
    "postbuild:public"
  ];

  npmCachePkgs = import inputs.npm-cache-nixpkgs {
    system = stdenv.hostPlatform.system;
  };

  piMcpAdapter = npmCachePkgs.buildNpmPackage {
    pname = "pi-mcp-adapter";
    version = piSources.pi-mcp-adapter.version;
    src = inputs.pi-mcp-adapter;
    patches = [ ./agent-resources/pi-mcp-adapter-xdg-config-home.patch ];
    npmDepsHash = piSources.pi-mcp-adapter.hashes.npmDepsHash;
    npmDepsFetcherVersion = 2;
    npmBuildScript = "build:public";
    postPatch = ''
      # Build the public exports explicitly after upstream moved the lifecycle
      # hook from prepare to prepack, while repairing the exact six nested Pi
      # lock entries published without integrity.
      ${python3}/bin/python3 - <<'PY'
      import json
      from pathlib import Path

      package = json.loads(Path("package.json").read_text())
      lock_path = Path("package-lock.json")
      lock = json.loads(lock_path.read_text())

      integrity_repairs = {
          "node_modules/@earendil-works/pi-coding-agent/node_modules/@earendil-works/pi-agent-core": (
              "https://registry.npmjs.org/@earendil-works/pi-agent-core/-/pi-agent-core-0.84.1.tgz",
              "sha512-evyzXYWCLQGmcaBYHlmSku02r8qoN4SGI60GZABo6iV+H+nqX+P9ud8fEZ4GmRq9mUSREvvfX+w9dA9ThF9C6w==",
          ),
          "node_modules/@earendil-works/pi-coding-agent/node_modules/@earendil-works/pi-ai": (
              "https://registry.npmjs.org/@earendil-works/pi-ai/-/pi-ai-0.84.1.tgz",
              "sha512-wMsAdJMxuNri08vLqTyYVI201DQQezGhPSTkzYsHdw5dYX3rCNwEmSvpaAwhi7ELKI/2tE/CEgSWg/6iRxSgdQ==",
          ),
          "node_modules/@earendil-works/pi-coding-agent/node_modules/@earendil-works/pi-client": (
              "https://registry.npmjs.org/@earendil-works/pi-client/-/pi-client-0.84.1.tgz",
              "sha512-/V5hGHE4Zq+jG0GtwIB9PyBUOGd6gBLZ7lkQYFKchKnxYHeH3rmWC5xw4kpnZKKBuBuFTdLVbU9vEjlAGMMb2A==",
          ),
          "node_modules/@earendil-works/pi-coding-agent/node_modules/@earendil-works/pi-protocol": (
              "https://registry.npmjs.org/@earendil-works/pi-protocol/-/pi-protocol-0.84.1.tgz",
              "sha512-Ox1pciyeSPGEEUcxvR0/dJcrY7C6hrEGA8y71rOsvSIUlXN1Cbp/be/eoL71OGDBk5O97TeQPfWN6Ju/2Ehjww==",
          ),
          "node_modules/@earendil-works/pi-coding-agent/node_modules/@earendil-works/pi-telemetry": (
              "https://registry.npmjs.org/@earendil-works/pi-telemetry/-/pi-telemetry-0.84.1.tgz",
              "sha512-180/xGJtsq7IoR3p9EKWjRd0e9M4DkxInhlo9xyD7prDC7Qrhqq+nhvwrW0lFjPfXcEI2FSHmGCSyvSJE9GsaQ==",
          ),
          "node_modules/@earendil-works/pi-coding-agent/node_modules/@earendil-works/pi-tui": (
              "https://registry.npmjs.org/@earendil-works/pi-tui/-/pi-tui-0.84.1.tgz",
              "sha512-udeXFbgEhJ6JiB0uguwNVNkDy2FENfmtQwPcY+/iJ8GWeq18wkal1tKqa5YyeH0IqtX1vG0cGh8zfSYzyzVuLA==",
          ),
      }

      missing_integrity = {
          path
          for path, metadata in lock["packages"].items()
          if path and metadata.get("resolved") and not metadata.get("integrity")
      }
      scripts = package.get("scripts", {})
      forbidden_build_scripts = set(${builtins.toJSON piMcpForbiddenBuildScripts})
      exports = package.get("exports", {})
      files = package.get("files", [])
      if not (
          scripts.get("build:public") == "tsc -p tsconfig.public.json"
          and scripts.get("prepack") == "npm run build:public"
          and forbidden_build_scripts.isdisjoint(scripts)
          and "dist" in files
          and exports.get("./types", {}).get("import") == "./dist/types.js"
          and exports.get("./config", {}).get("import") == "./dist/config.js"
          and exports.get("./metadata-cache", {}).get("import")
              == "./dist/metadata-cache.js"
          and Path("tsconfig.public.json").is_file()
      ):
          raise SystemExit("pi-mcp-adapter package build contract changed")

      if missing_integrity != set(integrity_repairs):
          raise SystemExit(
              "pi-mcp-adapter lock integrity omissions changed: "
              f"{sorted(missing_integrity)}"
          )
      for path, (resolved, integrity) in integrity_repairs.items():
          metadata = lock["packages"][path]
          if metadata.get("resolved") != resolved:
              raise SystemExit(f"pi-mcp-adapter lock source changed: {path}")
          metadata["integrity"] = integrity

      init_source = Path("init.ts").read_text()
      native_footer_contract = (
          'state.config.settings?.mcpFooterStatus ?? "full"',
          'typeof theme?.fg === "function"',
      )
      if any(init_source.count(fragment) != 1 for fragment in native_footer_contract):
          raise SystemExit("pi-mcp-adapter native footer-status contract changed")

      lock_path.write_text(json.dumps(lock, indent=2) + "\n")
      PY
    '';
    postInstall = ''
      ${python3}/bin/python3 - "$out/lib/node_modules/pi-mcp-adapter/package.json" <<'PY'
      import json
      from pathlib import Path
      import sys

      package_path = Path(sys.argv[1])
      package = json.loads(package_path.read_text())
      package.pop("devDependencies", None)
      package.pop("scripts", None)
      package_path.write_text(json.dumps(package, indent=2) + "\n")
      PY
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
  copy_skill ${lib.escapeShellArg "${../config/ai/skills/skill-creator}"} \
    skill-creator
  for script in ${skillCreatorScriptArgs}; do
    substituteInPlace "$skills/skill-creator/scripts/$script" \
      --replace-fail '#!/usr/bin/env python3' \
      '#!${skillCreatorPython}/bin/python3'
  done
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
