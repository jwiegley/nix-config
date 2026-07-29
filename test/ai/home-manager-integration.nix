{
  pkgs,
  src,
  agentResources,
  aiFlake,
  homeManagerLib,
  piGallery,
  inputs,
  testPkgsFor,
}:

let
  # The monolith had `lib` in scope via `inherit (pkgs) lib`; the extracted
  # runtime blocks still interpolate ${lib.optionalString ...}, so keep it.
  inherit (pkgs) lib;

  common = import ./home-manager-contract-common.nix {
    inherit
      pkgs
      src
      agentResources
      aiFlake
      homeManagerLib
      piGallery
      inputs
      testPkgsFor
      ;
  };

  # The ONLY check that evaluates Home Manager host configurations (full
  # activationPackage / home.path closures). It also owns the five task10
  # activation-wiring assertions, whose closure it already pays for.
  checks = common.task9Checks ++ common.task10ActivationWiringChecks;
in
assert builtins.deepSeq checks true;

pkgs.runCommand "ai-home-manager-integration"
  {
    nativeBuildInputs = [
      pkgs.findutils
      pkgs.jq
    ];
  }
  ''
    ${lib.optionalString (pkgs.stdenv.hostPlatform.system == "aarch64-darwin") ''
      profile_path="${common.task9JohnwHera.config.home.path}"
      test -x "$profile_path/bin/claude"
      test -x "$profile_path/bin/claude-real"
      test -x "$profile_path/bin/agent-http-header-bridge"
      test -x "$profile_path/bin/persona"
      grep -Fq 'classify_managed_artifacts' "$profile_path/bin/claude"
      ! grep -Fq 'classify_managed_artifacts' "$profile_path/bin/claude-real"
      test "$(readlink -e "$profile_path/bin/claude")" \
        = "$(readlink -e "${common.task9WrappedClaude}/bin/claude")"
      test "$(readlink -e "$profile_path/bin/claude-real")" \
        = "$(readlink -e "${common.task9WrappedClaude}/bin/claude-real")"
      test "$(readlink -e "$profile_path/bin/agent-http-header-bridge")" \
        = "$(readlink -e "${common.task9HeraBridge}/bin/agent-http-header-bridge")"
      test "$(readlink "${common.task9JohnwHera.config.home.file.".codex".source}")" \
        = "${common.task9JohnwHera.config.xdg.configHome}/codex"
      test "$(readlink "${common.task9JohnwHera.config.home.file.".factory".source}")" \
        = "${common.task9JohnwHera.config.xdg.configHome}/factory"
      test -f "${common.task9JohnwHera.config.home.file.".claude/skills/sherlock/SKILL.md".source}"

      droid_command="$("${pkgs.jq}/bin/jq" -er '.mcpServers.Ref.command' \
        "${common.task9JohnwHera.config.home.file.".config/factory/mcp.json".source}")"
      test "$droid_command" = agent-http-header-bridge

      fixture_home="${common.task9JohnwHera.config.home.homeDirectory}"
      profile_dir="${common.task9JohnwHera.config.home.profileDirectory}"
      legacy_bin="$fixture_home/src/scripts"
      rm -rf "$fixture_home"
      mkdir -p "$legacy_bin" "$fixture_home/.config/zsh"
      printf '#!/bin/sh\necho legacy-claude\n' > "$legacy_bin/claude"
      chmod +x "$legacy_bin/claude"
      ln -s "$profile_path" "$profile_dir"
      ln -s "${common.task9JohnwHera.config.home.file.".zshenv".source}" "$fixture_home/.zshenv"
      ln -s "${common.task9JohnwHera.config.home.file.".config/zsh/.zshenv".source}" \
        "$fixture_home/.config/zsh/.zshenv"
      ln -s "${common.task9JohnwHera.config.home.file.".config/zsh/.zprofile".source}" \
        "$fixture_home/.config/zsh/.zprofile"
      env -u __HM_SESS_VARS_SOURCED \
        -u __HM_ZSH_SESS_VARS_SOURCED \
        -u ZDOTDIR \
        TASK9_PROFILE="$profile_dir" \
        TASK9_DROID_COMMAND="$droid_command" \
        HOME="$fixture_home" \
        PATH="/usr/bin:/bin" \
        TERM=dumb \
        "${common.task9JohnwHera.config.programs.zsh.package}/bin/zsh" -l -c '
          set -eo pipefail
          case "$PATH" in
            "${common.task9JohnwHera.config.home.profileDirectory}/bin":*) ;;
            *) exit 1 ;;
          esac
          test "$(command -v claude)" = "$TASK9_PROFILE/bin/claude"
          test "$(command -v claude-real)" = "$TASK9_PROFILE/bin/claude-real"
          test "$(command -v "$TASK9_DROID_COMMAND")" \
            = "$TASK9_PROFILE/bin/$TASK9_DROID_COMMAND"
          test "$(command -v persona)" = "$TASK9_PROFILE/bin/persona"
        '
      rm -rf "${common.task9JohnwHera.config.home.homeDirectory}"

      activation="${common.task9Evaluations.hera.activationPackage}/activate"
      preflight_line="$(grep -nF '_iNote "Activating %s" "aiManagedPreflight"' "$activation" | head -1 | cut -d: -f1)"
      collision_line="$(grep -nF '_iNote "Activating %s" "checkLinkTargets"' "$activation" | head -1 | cut -d: -f1)"
      boundary_line="$(grep -nF '_iNote "Activating %s" "writeBoundary"' "$activation" | head -1 | cut -d: -f1)"
      links_line="$(grep -nF '_iNote "Activating %s" "linkGeneration"' "$activation" | head -1 | cut -d: -f1)"
      test -n "$preflight_line"
      test "$preflight_line" -lt "$collision_line"
      test "$collision_line" -lt "$boundary_line"
      test "$boundary_line" -lt "$links_line"
    ''}

    touch "$out"
  ''
