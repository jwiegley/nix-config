{
  pkgs,
  name,
  package,
}:

let
  managedArtifactClassifier = import ./managed-artifact-classifier.nix;

  codexWrapper = pkgs.writeShellScript "codex" ''
    set -euo pipefail
    set +x
    unset CODEX_INTERNAL_WRAPPER_POLICY_PROBE
    ${pkgs.lib.optionalString pkgs.stdenv.isDarwin ''
      # Raise the soft descriptor limit up to the inherited hard limit for Codex
      # and its descendants.
      codex_open_file_hard_limit="$(ulimit -Hn)"
      codex_open_file_limit=65536
      if [ "$codex_open_file_hard_limit" != unlimited ] \
        && [ "$codex_open_file_hard_limit" -lt "$codex_open_file_limit" ]; then
        codex_open_file_limit="$codex_open_file_hard_limit"
      fi
      ulimit -Sn "$codex_open_file_limit"
    ''}
    umask 077
    trap 'exit 129' HUP
    trap 'exit 130' INT
    trap 'exit 143' TERM

    # Keep CODEX_HOME shared while placing SQLite and log state on machine-local
    # storage.
    codex_shared_home="''${CODEX_HOME:-''${HOME:?}/.codex}"
    codex_uid="$(${pkgs.coreutils}/bin/id -u)"
    codex_local_root="/var/tmp/codex-$codex_uid"
    export CODEX_SQLITE_HOME="''${CODEX_SQLITE_HOME:-$codex_local_root/sqlite}"

    # /var/tmp is world-writable: fail closed, and loudly, if the
    # local root cannot be created or is not a plain directory we
    # own (pre-creation / symlink planting by another local user).
    # Falling back to the shared home would silently reintroduce
    # the cross-host corruption this wrapper exists to prevent.
    # The root is validated and locked down to 700 before anything
    # is created beneath it.
    if ! ${pkgs.coreutils}/bin/mkdir -p "$codex_local_root"; then
      echo "codex: cannot create host-local state under $codex_local_root" >&2
      exit 1
    fi
    if [ -L "$codex_local_root" ] || [ ! -d "$codex_local_root" ] \
      || [ "$(${pkgs.coreutils}/bin/stat -c %u "$codex_local_root")" != "$codex_uid" ]; then
      echo "codex: refusing $codex_local_root: not a directory owned by uid $codex_uid" >&2
      exit 1
    fi
    if ! ${pkgs.coreutils}/bin/chmod 700 "$codex_local_root" 2>/dev/null \
      || [ "$(${pkgs.coreutils}/bin/stat -c %a "$codex_local_root")" != 700 ]; then
      echo "codex: cannot secure host-local state under $codex_local_root" >&2
      exit 1
    fi
    if ! ${pkgs.coreutils}/bin/mkdir -p \
        "$codex_local_root/sqlite" "$codex_local_root/log"; then
      echo "codex: cannot create state directories under $codex_local_root" >&2
      exit 1
    fi
    for codex_state_dir in "$codex_local_root/sqlite" "$codex_local_root/log"; do
      if [ -L "$codex_state_dir" ] || [ ! -d "$codex_state_dir" ] \
        || [ "$(${pkgs.coreutils}/bin/stat -c %u "$codex_state_dir")" != "$codex_uid" ] \
        || ! ${pkgs.coreutils}/bin/chmod 700 "$codex_state_dir" 2>/dev/null \
        || [ "$(${pkgs.coreutils}/bin/stat -c %a "$codex_state_dir")" != 700 ]; then
        echo "codex: cannot secure state directory under $codex_local_root" >&2
        exit 1
      fi
    done

    # Seed the host-local memory database once using a directory mutex and a
    # same-directory temporary file; a failed attempt can retry next launch.
    if [ -f "$codex_shared_home/memories_1.sqlite" ] \
      && [ ! -e "$CODEX_SQLITE_HOME/memories_1.sqlite" ] \
      && ${pkgs.coreutils}/bin/mkdir "$CODEX_SQLITE_HOME/.memories-seed-lock" 2>/dev/null; then
      codex_seed_tmp="$CODEX_SQLITE_HOME/.memories_1.sqlite.seed.$$"
      trap '${pkgs.coreutils}/bin/rm -f "$codex_seed_tmp" 2>/dev/null;
            ${pkgs.coreutils}/bin/rmdir "$CODEX_SQLITE_HOME/.memories-seed-lock" 2>/dev/null' \
        EXIT
      if ${pkgs.coreutils}/bin/cp \
          "$codex_shared_home/memories_1.sqlite" "$codex_seed_tmp" 2>/dev/null; then
        ${pkgs.coreutils}/bin/mv -n \
          "$codex_seed_tmp" "$CODEX_SQLITE_HOME/memories_1.sqlite" 2>/dev/null || true
      fi
      ${pkgs.coreutils}/bin/rm -f "$codex_seed_tmp" 2>/dev/null || true
      ${pkgs.coreutils}/bin/rmdir "$CODEX_SQLITE_HOME/.memories-seed-lock" 2>/dev/null || true
      trap - EXIT
    fi

    # Point the shared log path at machine-local storage.
    codex_log_dir="$codex_shared_home/log"
    if [ ! -e "$codex_log_dir" ] && [ ! -L "$codex_log_dir" ] \
      && ! ${pkgs.coreutils}/bin/ln -s \
        "$codex_local_root/log" "$codex_log_dir" 2>/dev/null; then
      echo "codex: cannot create host-local log link" >&2
      exit 1
    fi
    if [ ! -L "$codex_log_dir" ] \
      || [ "$(${pkgs.coreutils}/bin/readlink "$codex_log_dir" 2>/dev/null)" != "$codex_local_root/log" ]; then
      echo "codex: refusing host-local log path" >&2
      exit 1
    fi

    ${managedArtifactClassifier}

    codex_managed_config="$codex_shared_home/nix-managed.config.toml"
    codex_runtime_config="$codex_local_root/nix-runtime.config.toml"
    codex_runtime_link="$codex_shared_home/nix-runtime.config.toml"

    codex_reject_runtime_profile() {
      printf 'codex: refusing unsafe runtime profile path: %s\n' "$1" >&2
      return 2
    }

    codex_prepare_runtime_profile() {
      local codex_runtime_owner codex_runtime_target codex_runtime_tmp

      if [ -L "$codex_runtime_config" ]; then
        codex_reject_runtime_profile "$codex_runtime_config"
      fi
      if [ -e "$codex_runtime_config" ]; then
        if [ ! -f "$codex_runtime_config" ]; then
          codex_reject_runtime_profile "$codex_runtime_config"
        fi
        if ! codex_runtime_owner="$(${pkgs.coreutils}/bin/stat -c %u \
            "$codex_runtime_config" 2>/dev/null)" \
          || [ "$codex_runtime_owner" != "$codex_uid" ]; then
          codex_reject_runtime_profile "$codex_runtime_config"
        fi
      fi

      if [ ! -e "$codex_runtime_link" ] && [ ! -L "$codex_runtime_link" ]; then
        ${pkgs.coreutils}/bin/ln -s \
          "$codex_runtime_config" "$codex_runtime_link" 2>/dev/null || true
      fi
      if [ ! -L "$codex_runtime_link" ]; then
        codex_reject_runtime_profile "$codex_runtime_link"
      fi
      if ! codex_runtime_target="$(${pkgs.coreutils}/bin/readlink \
          "$codex_runtime_link" 2>/dev/null)" \
        || [ "$codex_runtime_target" != "$codex_runtime_config" ]; then
        codex_reject_runtime_profile "$codex_runtime_link"
      fi

      if ! codex_runtime_tmp="$(${pkgs.coreutils}/bin/mktemp \
          "$codex_local_root/.nix-runtime.config.toml.XXXXXX" 2>/dev/null)"; then
        printf 'codex: cannot refresh host-local runtime profile\n' >&2
        return 2
      fi
      trap '${pkgs.coreutils}/bin/rm -f "$codex_runtime_tmp" 2>/dev/null || true' \
        EXIT
      if ! ${pkgs.coreutils}/bin/cp -- \
          "$codex_managed_config" "$codex_runtime_tmp" 2>/dev/null \
        || ! ${pkgs.coreutils}/bin/chmod 600 "$codex_runtime_tmp" 2>/dev/null; then
        ${pkgs.coreutils}/bin/rm -f "$codex_runtime_tmp" 2>/dev/null || true
        trap - EXIT
        printf 'codex: cannot refresh host-local runtime profile\n' >&2
        return 2
      fi

      # Recheck the destination immediately before the same-filesystem
      # rename.  -T prevents a directory from being treated as a move
      # target if the path changes after the initial validation.
      if [ -L "$codex_runtime_config" ] \
        || { [ -e "$codex_runtime_config" ] && [ ! -f "$codex_runtime_config" ]; }; then
        ${pkgs.coreutils}/bin/rm -f "$codex_runtime_tmp" 2>/dev/null || true
        trap - EXIT
        codex_reject_runtime_profile "$codex_runtime_config"
      fi
      if ! ${pkgs.coreutils}/bin/mv -fT -- \
          "$codex_runtime_tmp" "$codex_runtime_config" 2>/dev/null; then
        ${pkgs.coreutils}/bin/rm -f "$codex_runtime_tmp" 2>/dev/null || true
        trap - EXIT
        printf 'codex: cannot refresh host-local runtime profile\n' >&2
        return 2
      fi
      trap - EXIT
    }

    if [ "''${AI_NIX_BYPASS_MANAGED_CONFIG:-}" != 1 ]; then
      codex_state=$(classify_managed_artifacts "$codex_managed_config")
      case "$codex_state" in
        zero) ;;
        partial)
          printf 'codex: repair managed configuration artifact: %s\n' \
            "$codex_managed_config" >&2
          exit 2
          ;;
        complete)
          # The pinned binary owns argv grammar. Compare its pre-init response as
          # bytes in a private file so NULs, missing newlines, and extra output
          # cannot be normalized by shell command substitution.
          if ! codex_policy_file="$(${pkgs.coreutils}/bin/mktemp \
              "$codex_local_root/.wrapper-policy.XXXXXX" 2>/dev/null)"; then
            printf '%s\n' 'codex: unable to classify command safely' >&2
            exit 2
          fi
          trap '${pkgs.coreutils}/bin/rm -f "$codex_policy_file" 2>/dev/null || true' \
            EXIT
          if ! CODEX_INTERNAL_WRAPPER_POLICY_PROBE=v1 \
              @codex_unwrapped@ "$@" >"$codex_policy_file" 2>/dev/null; then
            ${pkgs.coreutils}/bin/rm -f "$codex_policy_file"
            trap - EXIT
            printf '%s\n' 'codex: unable to classify command safely' >&2
            exit 2
          fi

          codex_policy=invalid
          for codex_policy_candidate in \
            delegate conflict-profile conflict-ignore-user-config manage
          do
            if ${pkgs.coreutils}/bin/printf '%s\n' "$codex_policy_candidate" \
              | ${pkgs.diffutils}/bin/cmp -s - "$codex_policy_file"
            then
              codex_policy=$codex_policy_candidate
              break
            fi
          done
          ${pkgs.coreutils}/bin/rm -f "$codex_policy_file"
          trap - EXIT

          case "$codex_policy" in
            delegate)
              ;;
            conflict-profile)
              printf '%s\n' \
                'codex: managed configuration conflicts with a caller profile' >&2
              exit 2
              ;;
            conflict-ignore-user-config)
              printf '%s\n' \
                'codex: managed configuration conflicts with --ignore-user-config' >&2
              exit 2
              ;;
            manage)
              codex_prepare_runtime_profile
              unset CODEX_INTERNAL_WRAPPER_POLICY_PROBE
              exec -a codex @codex_unwrapped@ --profile nix-runtime "$@"
              ;;
            *)
              printf '%s\n' 'codex: unable to classify command safely' >&2
              exit 2
              ;;
          esac
          ;;
      esac
    fi

    exec -a codex @codex_unwrapped@ "$@"
  '';
in
pkgs.symlinkJoin {
  name = "${package.name or name}-host-state";
  paths = [ package ];
  postBuild = ''
    rm -f "$out/bin/codex"
    install -m 0755 ${codexWrapper} "$out/bin/codex"
    substituteInPlace "$out/bin/codex" \
      --replace-fail '@codex_unwrapped@' "${package}/bin/codex"
  '';
  passthru = (package.passthru or { }) // {
    unwrappedPackage = package;
  };
  meta = package.meta or { };
}
