{
  pkgs,
  name,
  package,
}:

let
  managedArtifactClassifier = ''
    classify_managed_artifacts() {
      local artifact
      local all_absent=1
      local all_regular=1

      [ "$#" -gt 0 ] || return 2
      for artifact in "$@"; do
        if [ -e "$artifact" ] || [ -L "$artifact" ]; then
          all_absent=0
        fi
        if [ ! -f "$artifact" ]; then
          all_regular=0
        fi
      done

      if [ "$all_absent" -eq 1 ]; then
        printf '%s\n' zero
      elif [ "$all_regular" -eq 1 ]; then
        printf '%s\n' complete
      else
        printf '%s\n' partial
      fi
    }
  '';

  droidWrapper = pkgs.writeShellScript "droid" ''
    set -euo pipefail

    if [ "''${AI_NIX_BYPASS_MANAGED_CONFIG:-}" = 1 ]; then
      exec -a droid @droid_unwrapped@ "$@"
    fi

    ${managedArtifactClassifier}

    droid_root="''${HOME:?}/.factory"
    droid_settings="$droid_root/nix-managed-settings.json"
    droid_mcp="$droid_root/mcp.json"

    droid_state=$(classify_managed_artifacts "$droid_settings" "$droid_mcp")
    case "$droid_state" in
      zero) ;;
      complete)
        for droid_argument in "$@"; do
          [ "$droid_argument" != -- ] || break
          case "$droid_argument" in
            --settings | --settings=*)
              printf '%s\n' \
                'droid: managed configuration conflicts with a caller option' >&2
              exit 2
              ;;
          esac
        done
        exec -a droid @droid_unwrapped@ --settings "$droid_settings" "$@"
        ;;
      partial)
        printf 'droid: repair managed configuration artifacts: %s %s\n' \
          "$droid_settings" "$droid_mcp" >&2
        exit 2
        ;;
    esac

    exec -a droid @droid_unwrapped@ "$@"
  '';
in
pkgs.symlinkJoin {
  name = "${package.name or name}-managed-config";
  paths = [ package ];
  postBuild = ''
    rm -f "$out/bin/droid"
    install -m 0755 ${droidWrapper} "$out/bin/droid"
    substituteInPlace "$out/bin/droid" \
      --replace-fail '@droid_unwrapped@' "${package}/bin/droid"
  '';
  meta = package.meta or { };
}
