{
  pkgs,
  name,
  package,
}:

let
  managedArtifactClassifier = import ./managed-artifact-classifier.nix;

  claudeWrapper = pkgs.writeShellScript "claude" ''
    set -euo pipefail

    if [ "''${AI_NIX_BYPASS_MANAGED_CONFIG:-}" = 1 ]; then
      exec -a claude @claude_unwrapped@ "$@"
    fi

    ${managedArtifactClassifier}

    claude_root="''${CLAUDE_CONFIG_DIR:-''${HOME:?}/.claude}"
    claude_settings="$claude_root/nix-managed-settings.json"
    claude_mcp="$claude_root/nix-managed-mcp.json"

    claude_state=$(classify_managed_artifacts "$claude_settings" "$claude_mcp")
    case "$claude_state" in
      zero) ;;
      complete)
        for claude_argument in "$@"; do
          [ "$claude_argument" != -- ] || break
          case "$claude_argument" in
            --settings | --settings=* | --mcp-config | --mcp-config=*)
              printf '%s\n' \
                'claude: managed configuration conflicts with a caller option' >&2
              exit 2
              ;;
          esac
        done
        exec -a claude @claude_unwrapped@ \
          --settings "$claude_settings" "--mcp-config=$claude_mcp" "$@"
        ;;
      partial)
        printf 'claude: repair managed configuration artifacts: %s %s\n' \
          "$claude_settings" "$claude_mcp" >&2
        exit 2
        ;;
    esac

    exec -a claude @claude_unwrapped@ "$@"
  '';
  claudeReal = pkgs.writeShellScript "claude-real" ''
    exec -a claude @claude_unwrapped@ "$@"
  '';
in
pkgs.symlinkJoin {
  name = "${package.name or name}-managed-config";
  paths = [ package ];
  postBuild = ''
    rm -f "$out/bin/claude" "$out/bin/claude-real"
    install -m 0755 ${claudeWrapper} "$out/bin/claude"
    install -m 0755 ${claudeReal} "$out/bin/claude-real"
    substituteInPlace "$out/bin/claude" "$out/bin/claude-real" \
      --replace-fail '@claude_unwrapped@' "${package}/bin/claude"
  '';
  meta = package.meta or { };
}
