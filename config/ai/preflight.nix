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
        printf '%s\n' \
          '${piGuard.path}: keep valid adapter JSON without top-level mcpServers or imports' >&2
        exit 1
      fi
    fi
  '';

  script = ''
    fail_collision() {
      printf '%s\n' "$1: remove or migrate the existing path before switching" >&2
      exit 1
    }

    fail_tamper() {
      printf '%s\n' "$1: restore the exact previous Home Manager link before switching" >&2
      exit 1
    }

    fail_previous_generation() {
      printf '%s\n' "$1: restore the previous Home Manager generation before switching" >&2
      exit 1
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

    check_previous_link() {
      path=$1
      current="$HOME/$path"
      if [ ! -L "$current" ] || [ ! -e "$current" ]; then
        fail_tamper "$path"
      fi
      actual_target="$(${pkgs.coreutils}/bin/readlink "$current" 2>/dev/null || true)"
      if [ "$actual_target" != "$old_files/$path" ]; then
        fail_tamper "$path"
      fi
    }

    old_files=
    if [[ -v oldGenPath ]]; then
      old_files="$(${pkgs.coreutils}/bin/readlink -e "$oldGenPath/home-files" 2>/dev/null || true)"
      if [ -z "$old_files" ] || [ ! -d "$old_files" ]; then
        fail_previous_generation "$oldGenPath/home-files"
      fi
    fi

    if [ -n "$old_files" ]; then
      if ${pkgs.findutils}/bin/find "$old_files" \( -type f -o -type l \) \
        -printf '%P\0' 2>/dev/null \
        | while IFS= read -r -d "" path; do
          if is_managed_ai_path "$path" && ! is_separate_writer "$path"; then
            check_previous_link "$path"
          fi
        done
      then
        pipeline_status=( "''${PIPESTATUS[@]}" )
      else
        pipeline_status=( "''${PIPESTATUS[@]}" )
      fi
      if [ "''${pipeline_status[1]}" -ne 0 ]; then
        exit "''${pipeline_status[1]}"
      fi
      if [ "''${pipeline_status[0]}" -ne 0 ]; then
        fail_previous_generation "$oldGenPath/home-files"
      fi
    fi

    while IFS= read -r path; do
      [ -n "$path" ] || continue
      if [ -n "$old_files" ] \
        && { [ -f "$old_files/$path" ] || [ -L "$old_files/$path" ]; }; then
        continue
      fi
      current="$HOME/$path"
      if [ -e "$current" ] || [ -L "$current" ]; then
        fail_collision "$path"
      fi
      parent="''${current%/*}"
      while [ "$parent" != "$HOME" ]; do
        if [ -L "$parent" ] || { [ -e "$parent" ] && [ ! -d "$parent" ]; }; then
          fail_collision "$path"
        fi
        parent="''${parent%/*}"
      done
    done < ${lib.escapeShellArg newPathsFile}

    ${piGuardScript}
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
