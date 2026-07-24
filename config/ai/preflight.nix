{ lib, pkgs }:

{
  newPaths,
  piGuard ? null,
}:

let
  sortedPaths = lib.sort builtins.lessThan (lib.unique newPaths);
  sherlockPaths = [
    ".claude/skills/sherlock"
    ".claude/skills/sherlock/SKILL.md"
    ".claude/skills/sherlock/sherlock"
  ];
  managedPrefixes = [
    ".agents/skills"
    ".claude/agents"
    ".claude/commands"
    ".claude/skills"
    ".codex/agents"
    ".config/claude/personal/agents"
    ".config/claude/personal/commands"
    ".config/claude/personal/skills"
    ".config/claude/positron/agents"
    ".config/claude/positron/commands"
    ".config/claude/positron/skills"
    ".config/codex/agents"
    ".config/factory/droids"
    ".config/factory/skills"
    ".config/opencode/agents"
    ".config/opencode/commands"
    ".config/opencode/skills"
    ".pi/agent/agents"
    ".pi/agent/prompts"
  ];
  managedExactPaths = [
    ".claude/nix-managed-mcp.json"
    ".claude/nix-managed-settings.json"
    ".claude/statusline-command.sh"
    ".codex/hooks.json"
    ".codex/nix-managed.config.toml"
    ".config/claude/personal/nix-managed-mcp.json"
    ".config/claude/personal/nix-managed-settings.json"
    ".config/claude/personal/statusline-command.sh"
    ".config/claude/positron/nix-managed-mcp.json"
    ".config/claude/positron/nix-managed-settings.json"
    ".config/claude/positron/statusline-command.sh"
    ".config/codex/hooks.json"
    ".config/codex/nix-managed.config.toml"
    ".config/factory/mcp.json"
    ".config/factory/nix-managed-settings.json"
    ".config/mcp/mcp.json"
    ".config/opencode/opencode.json"
    ".pi/agent/extensions/auto-compact-resume/index.ts"
    ".pi/agent/extensions/nix-gallery/index.ts"
    ".pi/agent/extensions/pi-mcp-adapter"
    ".pi/agent/extensions/pi-quiet"
    ".pi/agent/extensions/pi-subagent"
    ".pi/agent/keybindings.json"
    ".pi/agent/models.json"
  ];
  validRelativePath =
    path:
    let
      parts = lib.splitString "/" path;
    in
    path != ""
    && !(lib.hasPrefix "/" path)
    && builtins.all (part: part != "" && part != "." && part != "..") parts;
  validManagedPath =
    path:
    validRelativePath path
    && !(builtins.elem path sherlockPaths)
    && (
      builtins.elem path managedExactPaths
      || lib.any (prefix: lib.hasPrefix "${prefix}/" path) managedPrefixes
    );

  newPathsFile = pkgs.writeText "nix-managed-ai-paths" (
    lib.concatStringsSep "\n" sortedPaths + lib.optionalString (sortedPaths != [ ]) "\n"
  );
  progressMessage =
    let
      count = builtins.length sortedPaths;
      noun = if count == 1 then "path" else "paths";
    in
    "Checking ${toString count} Nix-managed AI leaf ${noun} for blockers...";
  piGuardValid =
    piGuard == null
    || (
      builtins.isAttrs piGuard
      &&
        builtins.attrNames piGuard == [
          "forbiddenKeys"
          "path"
        ]
      && piGuard.path == ".pi/agent/mcp.json"
      &&
        piGuard.forbiddenKeys == [
          "mcpServers"
          "imports"
        ]
    );
  piGuardScript = lib.optionalString (piGuard != null) ''
    pi_path="$HOME/${piGuard.path}"
    if [ -e "$pi_path" ] || [ -L "$pi_path" ]; then
      if [ ! -f "$pi_path" ] || ! ${pkgs.jq}/bin/jq -e \
        'if type == "object"
         then ((has("mcpServers") or has("imports")) | not)
         else false
         end' \
        "$pi_path" >/dev/null 2>&1; then
        report_error \
          '${piGuard.path}: keep valid adapter JSON without top-level mcpServers or imports'
      fi
    fi
  '';

  script = ''
    errors_file="$(${pkgs.coreutils}/bin/mktemp \
      "''${TMPDIR:-/tmp}/nix-managed-ai-preflight.XXXXXX")"
    printf '%s\n' ${lib.escapeShellArg progressMessage}

    report_error() {
      printf '%s\n' "$1" >> "$errors_file"
    }

    path_kind() {
      if [ -L "$1" ]; then
        printf '%s' symlink
      elif [ -f "$1" ]; then
        printf '%s' 'regular file'
      elif [ -d "$1" ]; then
        printf '%s' directory
      elif [ -p "$1" ]; then
        printf '%s' FIFO
      elif [ -S "$1" ]; then
        printf '%s' socket
      elif [ -b "$1" ]; then
        printf '%s' 'block device'
      elif [ -c "$1" ]; then
        printf '%s' 'character device'
      else
        printf '%s' 'special path'
      fi
    }

    report_leaf_collision() {
      path=$1
      current=$2
      kind="$(path_kind "$current")"
      report_error "$path: blocking leaf is a $kind: $current"
    }

    report_external_symlink() {
      path=$1
      current=$2
      report_error "$path: blocking leaf is a symlink outside the Nix store: $current"
    }

    symlink_targets_nix_store() {
      current=$1
      normalized="$(${pkgs.coreutils}/bin/readlink -m -- "$current" 2>/dev/null || true)"
      case "$normalized" in
        ${builtins.storeDir} | ${builtins.storeDir}/*) return 0 ;;
      esac
      return 1
    }

    report_parent_collision() {
      path=$1
      parent=$2
      kind=$3
      case "$kind" in
        [aeiouAEIOU]*) article=an ;;
        *) article=a ;;
      esac
      report_error "$path: blocking parent is $article $kind: $parent"
    }

    check_shared_alias() {
      path=$1
      parent=$2
      resolved="$(${pkgs.coreutils}/bin/readlink -e "$parent" 2>/dev/null || true)"
      if [ -z "$resolved" ] || [ ! -d "$resolved" ] || [ ! -x "$resolved" ]; then
        report_parent_collision "$path" "$parent" 'unusable symlink'
        return 1
      fi
      case "$resolved" in
        ${builtins.storeDir} | ${builtins.storeDir}/*)
          report_error "$path: blocking parent is a symlink into the Nix store: $parent"
          return 1
          ;;
      esac
      if [ ! -w "$resolved" ]; then
        report_error \
          "$path: blocking parent is a symlink to an unwritable directory: $parent"
        return 1
      fi
      return 0
    }

    check_traversable_parent() {
      path=$1
      parent=$2
      if [ -L "$parent" ]; then
        if ! check_shared_alias "$path" "$parent"; then
          return 1
        fi
      elif [ -d "$parent" ]; then
        if [ ! -x "$parent" ]; then
          report_parent_collision "$path" "$parent" 'unsearchable directory'
          return 1
        fi
      elif [ -e "$parent" ]; then
        report_parent_collision "$path" "$parent" "$(path_kind "$parent")"
        return 1
      else
        report_parent_collision "$path" "$parent" 'missing directory'
        return 1
      fi
      return 0
    }

    check_writable_parent() {
      path=$1
      parent=$2
      if [ -L "$parent" ]; then
        if ! check_shared_alias "$path" "$parent"; then
          return 1
        fi
      elif [ -d "$parent" ]; then
        if [ ! -w "$parent" ] && [ ! -x "$parent" ]; then
          report_parent_collision "$path" "$parent" \
            'unwritable and unsearchable directory'
          return 1
        elif [ ! -w "$parent" ]; then
          report_parent_collision "$path" "$parent" 'unwritable directory'
          return 1
        elif [ ! -x "$parent" ]; then
          report_parent_collision "$path" "$parent" 'unsearchable directory'
          return 1
        fi
      elif [ -e "$parent" ]; then
        report_parent_collision "$path" "$parent" "$(path_kind "$parent")"
        return 1
      else
        report_parent_collision "$path" "$parent" 'missing directory'
        return 1
      fi
      return 0
    }

    check_path_parents() {
      path=$1
      parent="$HOME"
      remaining="''${path%/*}"

      while [ -n "$remaining" ]; do
        case "$remaining" in
          */*)
            component="''${remaining%%/*}"
            remaining="''${remaining#*/}"
            ;;
          *)
            component="$remaining"
            remaining=
            ;;
        esac
        candidate="$parent/$component"

        if [ -L "$candidate" ] || [ -d "$candidate" ]; then
          if [ -n "$remaining" ]; then
            if ! check_traversable_parent "$path" "$candidate"; then
              return 1
            fi
          elif ! check_writable_parent "$path" "$candidate"; then
            return 1
          fi
        elif [ -e "$candidate" ]; then
          report_parent_collision "$path" "$candidate" "$(path_kind "$candidate")"
          return 1
        else
          check_writable_parent "$path" "$parent"
          return $?
        fi
        parent="$candidate"
      done
      return 0
    }

    check_existing_managed_leaf() {
      path=$1
      current="$HOME/$path"
      if [ ! -e "$current" ] && [ ! -L "$current" ]; then
        return 0
      fi
      if [ -L "$current" ]; then
        if symlink_targets_nix_store "$current"; then
          return 0
        fi
        report_external_symlink "$path" "$current"
        return 0
      fi
      report_leaf_collision "$path" "$current"
      return 0
    }

    while IFS= read -r path; do
      [ -n "$path" ] || continue
      if ! check_path_parents "$path"; then
        continue
      fi
      check_existing_managed_leaf "$path"
    done < ${lib.escapeShellArg newPathsFile}

    ${piGuardScript}

    if [ -s "$errors_file" ]; then
      LC_ALL=C ${pkgs.coreutils}/bin/sort -u "$errors_file" >&2
      ${pkgs.coreutils}/bin/rm -f "$errors_file"
      exit 1
    fi
    ${pkgs.coreutils}/bin/rm -f "$errors_file"
  '';
in
assert builtins.isList newPaths;
assert newPaths == sortedPaths;
assert builtins.all validManagedPath newPaths;
assert piGuardValid;
{
  inherit script;
  activation = lib.hm.dag.entryBefore [ "checkLinkTargets" ] script;
}
