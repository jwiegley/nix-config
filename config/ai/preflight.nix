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
    ".codex/nix-managed.config.toml"
    ".config/claude/personal/nix-managed-mcp.json"
    ".config/claude/personal/nix-managed-settings.json"
    ".config/claude/personal/statusline-command.sh"
    ".config/claude/positron/nix-managed-mcp.json"
    ".config/claude/positron/nix-managed-settings.json"
    ".config/claude/positron/statusline-command.sh"
    ".config/codex/nix-managed.config.toml"
    ".config/factory/mcp.json"
    ".config/factory/nix-managed-settings.json"
    ".config/mcp/mcp.json"
    ".config/opencode/opencode.json"
    ".pi/agent/extensions/pi-mcp-adapter"
    ".pi/agent/extensions/pi-quiet"
    ".pi/agent/extensions/pi-subagent"
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

    report_tamper() {
      report_error "$1: restore the exact previous Home Manager link before switching"
    }

    report_previous_generation() {
      report_error "$1: restore the previous Home Manager generation before switching"
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

    is_managed_ai_path() {
      case "$1" in
        .agents/skills/* | \
        .claude/agents/* | .claude/commands/* | .claude/skills/* | \
        .codex/agents/* | \
        .config/claude/personal/agents/* | \
        .config/claude/personal/commands/* | \
        .config/claude/personal/skills/* | \
        .config/claude/positron/agents/* | \
        .config/claude/positron/commands/* | \
        .config/claude/positron/skills/* | \
        .config/codex/agents/* | \
        .config/factory/droids/* | .config/factory/skills/* | \
        .config/opencode/agents/* | \
        .config/opencode/commands/* | \
        .config/opencode/skills/* | \
        .pi/agent/agents/* | .pi/agent/prompts/* | \
        .claude/nix-managed-mcp.json | \
        .claude/nix-managed-settings.json | \
        .claude/statusline-command.sh | \
        .codex/nix-managed.config.toml | \
        .config/claude/personal/nix-managed-mcp.json | \
        .config/claude/personal/nix-managed-settings.json | \
        .config/claude/personal/statusline-command.sh | \
        .config/claude/positron/nix-managed-mcp.json | \
        .config/claude/positron/nix-managed-settings.json | \
        .config/claude/positron/statusline-command.sh | \
        .config/codex/nix-managed.config.toml | \
        .config/factory/mcp.json | \
        .config/factory/nix-managed-settings.json | \
        .config/mcp/mcp.json | \
        .config/opencode/opencode.json | \
        .pi/agent/extensions/pi-mcp-adapter | \
        .pi/agent/extensions/pi-quiet | \
        .pi/agent/extensions/pi-subagent | \
        .pi/agent/models.json | \
        .local/bin/claude)
          return 0
          ;;
      esac
      return 1
    }

    is_separate_writer() {
      case "$1" in
        .claude/skills/sherlock/SKILL.md | \
        .claude/skills/sherlock/sherlock)
          return 0
          ;;
      esac
      return 1
    }

    old_path_has_real_parents() {
      path=$1
      relative_parent="''${path%/*}"
      candidate="$old_files"
      remaining="$relative_parent"

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
        candidate="$candidate/$component"
        if [ -L "$candidate" ] || [ ! -d "$candidate" ]; then
          return 1
        fi
      done
      return 0
    }

    old_leaf_is_managed() {
      path=$1
      [ -n "$old_files" ] || return 1
      old_path_has_real_parents "$path" || return 1
      [ -f "$old_files/$path" ] || [ -L "$old_files/$path" ]
    }

    check_previous_link() {
      path=$1
      current="$HOME/$path"
      if [ ! -L "$current" ] || [ ! -e "$current" ]; then
        report_tamper "$path"
        return 0
      fi
      actual_target="$(${pkgs.coreutils}/bin/readlink "$current" 2>/dev/null || true)"
      if [ "$actual_target" != "$old_files/$path" ]; then
        report_tamper "$path"
      fi
      return 0
    }

    old_files=
    old_generation_valid=true
    if [[ -v oldGenPath ]]; then
      old_files="$(${pkgs.coreutils}/bin/readlink -e "$oldGenPath/home-files" 2>/dev/null || true)"
      if [ -z "$old_files" ] || [ ! -d "$old_files" ]; then
        report_previous_generation "$oldGenPath/home-files"
        old_generation_valid=false
      fi
    fi

    if [ "$old_generation_valid" = true ] && [ -n "$old_files" ]; then
      if ${pkgs.findutils}/bin/find "$old_files" \( -type f -o -type l \) \
        -printf '%P\0' 2>/dev/null \
        | while IFS= read -r -d "" path; do
          if is_managed_ai_path "$path" && ! is_separate_writer "$path"; then
            check_previous_link "$path"
            if ! check_path_parents "$path"; then
              :
            fi
          fi
        done
      then
        pipeline_status=( "''${PIPESTATUS[@]}" )
      else
        pipeline_status=( "''${PIPESTATUS[@]}" )
      fi
      if [ "''${pipeline_status[1]}" -ne 0 ]; then
        report_previous_generation "$oldGenPath/home-files"
      fi
      if [ "''${pipeline_status[0]}" -ne 0 ]; then
        report_previous_generation "$oldGenPath/home-files"
      fi
    fi

    while IFS= read -r path; do
      [ -n "$path" ] || continue
      was_managed=false
      if [ "$old_generation_valid" = true ] && old_leaf_is_managed "$path"; then
        was_managed=true
      fi

      if ! check_path_parents "$path"; then
        continue
      fi

      if [ "$old_generation_valid" != true ] || [ "$was_managed" = true ]; then
        continue
      fi

      current="$HOME/$path"
      if [ -e "$current" ] || [ -L "$current" ]; then
        report_leaf_collision "$path" "$current"
      fi
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
