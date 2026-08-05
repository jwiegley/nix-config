{ lib, pkgs }:

{
  blackholeConfigPath ? null,
  newPaths,
  piGuard ? null,
  piAliasTarget ? null,
  retiredPaths ? [ ],
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
    ".config/pi/agent/agents"
    ".config/pi/agent/prompts"
  ];
  managedExactPaths = [
    ".claude/nix-managed-mcp.json"
    ".claude/nix-managed-settings.json"
    ".claude/statusline-command.sh"
    ".codex/hooks.json"
    ".codex/nix-managed.config.toml"
    ".codex/nix-managed-model-catalog.json"
    ".config/claude/personal/nix-managed-mcp.json"
    ".config/claude/personal/nix-managed-settings.json"
    ".config/claude/personal/statusline-command.sh"
    ".config/claude/positron/nix-managed-mcp.json"
    ".config/claude/positron/nix-managed-settings.json"
    ".config/claude/positron/statusline-command.sh"
    ".config/codex/hooks.json"
    ".config/codex/nix-managed.config.toml"
    ".config/codex/nix-managed-model-catalog.json"
    ".config/factory/mcp.json"
    ".config/mcp/mcp.json"
    ".pi-lens/config.json"
    ".config/pi/agent/extensions/fleet-theme/index.ts"
    ".config/pi/agent/extensions/nix-gallery/index.ts"
    ".config/pi/agent/extensions/pi-loop/index.ts"
    ".config/pi/agent/extensions/pi-mcp-adapter"
    ".config/pi/agent/extensions/pi-quiet"
    ".config/pi/agent/keybindings.json"
    ".config/pi/agent/model-router.json"
    ".config/pi/agent/models.json"
    ".config/pi/agent/themes/dark-tool-backgrounds.json"
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
    if piGuard == null then
      true
    else
      (
        builtins.isAttrs piGuard
        &&
          builtins.attrNames piGuard == [
            "forbiddenKeys"
            "path"
          ]
        && piGuard.path == ".config/pi/agent/mcp.json"
        &&
          piGuard.forbiddenKeys == [
            "mcpServers"
            "imports"
          ]
      );
  piAliasTargetValid = piAliasTarget == null || validRelativePath piAliasTarget;
  blackholeConfigPathValid =
    blackholeConfigPath == null
    || (
      validRelativePath blackholeConfigPath
      && lib.hasSuffix "/pi/agent/pi-blackhole/pi-blackhole-config.json" blackholeConfigPath
    );
  retiredPathsValid =
    retiredPaths == lib.sort builtins.lessThan (lib.unique retiredPaths)
    && builtins.all (
      path:
      validRelativePath path && lib.hasSuffix "/pi/agent/extensions/auto-compact-resume/index.ts" path
    ) retiredPaths;
  piGuardPaths = lib.optional (piGuard != null) piGuard.path;
  renderPiGuard = path: ''
    pi_path="$HOME/${path}"
    if [ -e "$pi_path" ] || [ -L "$pi_path" ]; then
      if [ ! -f "$pi_path" ] || ! ${pkgs.jq}/bin/jq -e \
        'if type == "object"
         then ((has("mcpServers") or has("imports")) | not)
         else false
         end' \
        "$pi_path" >/dev/null 2>&1; then
        report_error \
          '${path}: keep valid adapter JSON without top-level mcpServers or imports'
      fi
    fi
  '';
  piGuardScript = lib.concatMapStringsSep "\n" renderPiGuard piGuardPaths;

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

    ${lib.optionalString (piAliasTarget != null) ''
      pi_alias="$HOME/.pi"
      pi_alias_expected="$HOME/${piAliasTarget}"
      if [ -L "$pi_alias" ]; then
        pi_alias_resolved="$(${pkgs.coreutils}/bin/readlink -e -- "$pi_alias" 2>/dev/null || true)"
        pi_alias_expected_resolved="$(${pkgs.coreutils}/bin/readlink -m -- "$pi_alias_expected")"
        if [ -z "$pi_alias_resolved" ] \
          || [ "$pi_alias_resolved" != "$pi_alias_expected_resolved" ]; then
          report_error ".pi: compatibility link must resolve to $pi_alias_expected"
        fi
      elif [ -e "$pi_alias" ]; then
        report_error ".pi: preserve and reconcile the existing $(path_kind "$pi_alias") before activation"
      fi
    ''}

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

    ${lib.concatMapStringsSep "\n" (path: ''
      retired_path=${lib.escapeShellArg path}
      retired_current="$HOME/$retired_path"
      if [ -e "$retired_current" ] || [ -L "$retired_current" ]; then
        retired_target="$(${pkgs.coreutils}/bin/readlink -- "$retired_current" 2>/dev/null || true)"
        case "$retired_target" in
          ${builtins.storeDir}/*-home-manager-files/"$retired_path") ;;
          *)
            report_error \
              "$retired_path: retired extension must be absent or linked from a prior Home Manager generation"
            ;;
        esac
      fi
    '') retiredPaths}

    ${lib.optionalString (blackholeConfigPath != null) ''
      blackhole_path="$HOME/${blackholeConfigPath}"
      blackhole_dir="''${blackhole_path%/*}"
      if [ -L "$blackhole_dir" ] \
        || { [ -e "$blackhole_dir" ] && [ ! -d "$blackhole_dir" ]; }; then
        report_error \
          "${blackholeConfigPath}: parent must be a directory, not $(path_kind "$blackhole_dir")"
      elif [ -L "$blackhole_path" ] \
        || { [ -e "$blackhole_path" ] && [ ! -f "$blackhole_path" ]; }; then
        report_error \
          "${blackholeConfigPath}: configuration must be a regular file"
      elif [ -f "$blackhole_path" ] \
        && ! ${pkgs.jq}/bin/jq -e 'type == "object"' "$blackhole_path" >/dev/null 2>&1; then
        report_error \
          "${blackholeConfigPath}: configuration must be a valid JSON object"
      fi
    ''}

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
assert piAliasTargetValid;
assert blackholeConfigPathValid;
assert retiredPathsValid;
{
  inherit script;
  activation = lib.hm.dag.entryBefore [ "checkLinkTargets" ] script;
}
