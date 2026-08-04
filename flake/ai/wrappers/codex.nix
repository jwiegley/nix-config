{
  pkgs,
  name,
  package,
}:

let
  managedArtifactClassifier = import ./managed-artifact-classifier.nix;

  # app is a command only on Darwin among supported outputs.
  codexAppCommandCase = pkgs.lib.optionalString pkgs.stdenv.isDarwin " | app";
  codexSandboxDarwinValueCase = pkgs.lib.optionalString pkgs.stdenv.isDarwin " | --allow-unix-socket";
  codexSandboxDarwinAttachedCase = pkgs.lib.optionalString pkgs.stdenv.isDarwin " | --allow-unix-socket=?*";
  codexSandboxDarwinFlagCase = pkgs.lib.optionalString pkgs.stdenv.isDarwin " | --log-denials";
  codexWrapper = pkgs.writeShellScript "codex" ''
    set -euo pipefail
    set +x
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
        EXIT INT TERM
      if ${pkgs.coreutils}/bin/cp \
          "$codex_shared_home/memories_1.sqlite" "$codex_seed_tmp" 2>/dev/null; then
        ${pkgs.coreutils}/bin/mv -n \
          "$codex_seed_tmp" "$CODEX_SQLITE_HOME/memories_1.sqlite" 2>/dev/null || true
      fi
      ${pkgs.coreutils}/bin/rm -f "$codex_seed_tmp" 2>/dev/null || true
      ${pkgs.coreutils}/bin/rmdir "$CODEX_SQLITE_HOME/.memories-seed-lock" 2>/dev/null || true
      trap - EXIT INT TERM
    fi

    # Point the shared log path at machine-local storage.
    codex_log_dir="$codex_shared_home/log"
    if [ -d "$codex_log_dir" ] && [ ! -L "$codex_log_dir" ]; then
      if ! ${pkgs.coreutils}/bin/rmdir "$codex_log_dir" 2>/dev/null \
        && ! ${pkgs.coreutils}/bin/mv \
          "$codex_log_dir" "$codex_log_dir.pre-host-state.$$" 2>/dev/null; then
        echo "codex: cannot migrate host-local log path" >&2
        exit 1
      fi
    fi
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

    # This is intentionally not a Codex CLI validator. It mirrors only the
    # profile-applicability boundary in pinned
    # codex-rs/cli/src/main.rs::profile_v2_for_subcommand. The scanners retain
    # only the option arity needed to locate command, profile, help, and payload
    # boundaries; the packaged Clap parser owns values, combinations, and
    # positional counts.
    codex_profile_name_is_valid() {
      [[ "$1" =~ ^[A-Za-z0-9_-]+$ ]]
    }

    codex_scan_profile_at() {
      local codex_profile_value codex_profile_width

      case "''${codex_arguments[$codex_index]}" in
        -p | --profile)
          if [ $((codex_index + 1)) -ge "''${#codex_arguments[@]}" ]; then
            return 1
          fi
          codex_profile_value="''${codex_arguments[$((codex_index + 1))]}"
          case "$codex_profile_value" in
            -) ;;
            -*) return 1 ;;
          esac
          codex_profile_width=2
          ;;
        --profile=*)
          codex_profile_value="''${codex_arguments[$codex_index]#--profile=}"
          codex_profile_width=1
          ;;
        -p=*)
          codex_profile_value="''${codex_arguments[$codex_index]#-p=}"
          codex_profile_width=1
          ;;
        -p?*)
          codex_profile_value="''${codex_arguments[$codex_index]#-p}"
          codex_profile_width=1
          ;;
        *) return 1 ;;
      esac

      codex_profile_name_is_valid "$codex_profile_value" || return 1
      case "$codex_profile_scope" in
        root)
          codex_root_profiles=$((codex_root_profiles + 1))
          ;;
        local)
          codex_local_profiles=$((codex_local_profiles + 1))
          ;;
      esac
      codex_index=$((codex_index + codex_profile_width))
    }

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
        EXIT INT TERM
      if ! ${pkgs.coreutils}/bin/cp -- \
          "$codex_managed_config" "$codex_runtime_tmp" 2>/dev/null \
        || ! ${pkgs.coreutils}/bin/chmod 600 "$codex_runtime_tmp" 2>/dev/null; then
        ${pkgs.coreutils}/bin/rm -f "$codex_runtime_tmp" 2>/dev/null || true
        trap - EXIT INT TERM
        printf 'codex: cannot refresh host-local runtime profile\n' >&2
        return 2
      fi

      # Recheck the destination immediately before the same-filesystem
      # rename.  -T prevents a directory from being treated as a move
      # target if the path changes after the initial validation.
      if [ -L "$codex_runtime_config" ] \
        || { [ -e "$codex_runtime_config" ] && [ ! -f "$codex_runtime_config" ]; }; then
        ${pkgs.coreutils}/bin/rm -f "$codex_runtime_tmp" 2>/dev/null || true
        trap - EXIT INT TERM
        codex_reject_runtime_profile "$codex_runtime_config"
      fi
      if ! ${pkgs.coreutils}/bin/mv -fT -- \
          "$codex_runtime_tmp" "$codex_runtime_config" 2>/dev/null; then
        ${pkgs.coreutils}/bin/rm -f "$codex_runtime_tmp" 2>/dev/null || true
        trap - EXIT INT TERM
        printf 'codex: cannot refresh host-local runtime profile\n' >&2
        return 2
      fi
      trap - EXIT INT TERM
    }

    # Carry the pre-Nix Ref credential into Codex's native environment-header carrier.
    codex_import_legacy_ref_api_key() {
      local codex_ref_api_key codex_ref_line

      [ -z "''${REF_API_KEY:-}" ] || return 0
      while IFS= read -r codex_ref_line; do
        case "$codex_ref_line" in
          "  url: https://api.ref.tools/mcp?apiKey="*)
            codex_ref_api_key="''${codex_ref_line#*apiKey=}"
            [[ "$codex_ref_api_key" =~ ^ref-[A-Za-z0-9_-]+$ ]] || return 0
            REF_API_KEY=$codex_ref_api_key
            export REF_API_KEY
            return 0
            ;;
        esac
      done < <(@codex_unwrapped@ mcp get Ref 2>/dev/null || true)
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
          codex_arguments=("$@")
          codex_root_profiles=0
          codex_local_profiles=0
          codex_ignore_user_config=0
          codex_scan_ok=1
          codex_route=delegate
          codex_command=
          codex_command_index=-1
          codex_index=0

          # Locate only the root command boundary. A separated image option is
          # greedy upstream, so every following non-option belongs to it.
          while [ "$codex_index" -lt "''${#codex_arguments[@]}" ]; do
            codex_argument="''${codex_arguments[$codex_index]}"
            case "$codex_argument" in
              --)
                codex_index="''${#codex_arguments[@]}"
                break
                ;;
              -h | --help | -V | --version)
                codex_scan_ok=0
                break
                ;;
              -p | --profile | --profile=* | -p=* | -p?*)
                codex_profile_scope=root
                if ! codex_scan_profile_at; then
                  codex_scan_ok=0
                  break
                fi
                continue
                ;;
              -i | --image)
                codex_index=$((codex_index + 1))
                codex_image_count=0
                while [ "$codex_index" -lt "''${#codex_arguments[@]}" ]; do
                  codex_option_value="''${codex_arguments[$codex_index]}"
                  case "$codex_option_value" in
                    -) ;;
                    -*) break ;;
                  esac
                  codex_image_count=$((codex_image_count + 1))
                  codex_index=$((codex_index + 1))
                done
                if [ "$codex_image_count" -eq 0 ]; then
                  codex_scan_ok=0
                  break
                fi
                continue
                ;;
              -c | --config | --enable | --disable | --remote | \
              --remote-auth-token-env | -m | --model | --local-provider | \
              -s | --sandbox | -C | --cd | --add-dir | \
              -a | --ask-for-approval)
                if [ $((codex_index + 1)) -ge "''${#codex_arguments[@]}" ]; then
                  codex_scan_ok=0
                  break
                fi
                codex_option_value="''${codex_arguments[$((codex_index + 1))]}"
                case "$codex_option_value" in
                  -) ;;
                  -*)
                    codex_scan_ok=0
                    break
                    ;;
                esac
                [ "$codex_scan_ok" -eq 1 ] || break
                codex_index=$((codex_index + 2))
                continue
                ;;
              --config=* | -c?* | --enable=* | --disable=* | \
              --remote=* | --remote-auth-token-env=* | --model=* | -m?* | \
              --local-provider=* | --sandbox=* | -s?* | --cd=* | -C?* | \
              --add-dir=* | --ask-for-approval=* | -a?* | \
              --image=* | -i?* | --strict-config | --oss | \
              --dangerously-bypass-approvals-and-sandbox | --yolo | \
              --dangerously-bypass-hook-trust | --search | --no-alt-screen)
                codex_index=$((codex_index + 1))
                continue
                ;;
              -)
                codex_index=$((codex_index + 1))
                continue
                ;;
              -*)
                codex_scan_ok=0
                break
                ;;
              *)
                case "$codex_argument" in
                  exec | e | review | login | logout | mcp | plugin | \
                  mcp-server | app-server | remote-control | completion | \
                  update | doctor | sandbox | debug | execpolicy | apply | a | \
                  resume | archive | delete | unarchive | fork | cloud | \
                  cloud-tasks | responses-api-proxy | stdio-to-uds | \
                  exec-server | features | help${codexAppCommandCase})
                    codex_command="$codex_argument"
                    codex_command_index=$codex_index
                    break
                    ;;
                  *)
                    codex_index=$((codex_index + 1))
                    continue
                    ;;
                esac
                ;;
            esac
          done

          if [ "$codex_scan_ok" -eq 1 ]; then
            if [ "$codex_command_index" -eq -1 ]; then
              codex_route=manage
            else
              case "$codex_command" in
                exec | e)
                  codex_route=manage
                  codex_index=$((codex_command_index + 1))
                  while [ "$codex_index" -lt "''${#codex_arguments[@]}" ]; do
                    codex_argument="''${codex_arguments[$codex_index]}"
                    case "$codex_argument" in
                      --)
                        break
                        ;;
                      -h | --help | -V | --version)
                        codex_scan_ok=0
                        break
                        ;;
                      -p | --profile | --profile=* | -p=* | -p?*)
                        codex_profile_scope=local
                        if ! codex_scan_profile_at; then
                          codex_scan_ok=0
                          break
                        fi
                        continue
                        ;;
                      --ignore-user-config)
                        codex_ignore_user_config=1
                        codex_index=$((codex_index + 1))
                        continue
                        ;;
                      -i | --image)
                        codex_index=$((codex_index + 1))
                        codex_image_count=0
                        while [ "$codex_index" -lt "''${#codex_arguments[@]}" ]; do
                          codex_option_value="''${codex_arguments[$codex_index]}"
                          case "$codex_option_value" in
                            -) ;;
                            -*) break ;;
                          esac
                          codex_image_count=$((codex_image_count + 1))
                          codex_index=$((codex_index + 1))
                        done
                        if [ "$codex_image_count" -eq 0 ]; then
                          codex_scan_ok=0
                          break
                        fi
                        continue
                        ;;
                      -c | --config | --enable | --disable | -m | --model | \
                      --local-provider | -s | --sandbox | -C | --cd | \
                      --add-dir | --output-schema | --color | -o | \
                      --output-last-message)
                        if [ $((codex_index + 1)) -ge "''${#codex_arguments[@]}" ]; then
                          codex_scan_ok=0
                          break
                        fi
                        codex_option_value="''${codex_arguments[$((codex_index + 1))]}"
                        case "$codex_option_value" in
                          -) ;;
                          -*)
                            codex_scan_ok=0
                            break
                            ;;
                        esac
                        [ "$codex_scan_ok" -eq 1 ] || break
                        codex_index=$((codex_index + 2))
                        continue
                        ;;
                      --config=* | -c?* | --enable=* | --disable=* | \
                      --image=* | -i?* | --model=* | -m?* | \
                      --local-provider=* | --sandbox=* | -s?* | --cd=* | \
                      -C?* | --add-dir=* | --output-schema=* | --color=* | \
                      --output-last-message=* | -o?* | --oss | \
                      --dangerously-bypass-approvals-and-sandbox | --yolo | \
                      --dangerously-bypass-hook-trust | --strict-config | \
                      --skip-git-repo-check | --ephemeral | \
                      --ignore-rules | --json | \
                      --experimental-json | --full-auto)
                        codex_index=$((codex_index + 1))
                        continue
                        ;;
                      -)
                        codex_index=$((codex_index + 1))
                        continue
                        ;;
                      -?*)
                        codex_scan_ok=0
                        break
                        ;;
                      *)
                        case "$codex_argument" in
                          help)
                            codex_scan_ok=0
                            break
                            ;;
                          resume | review)
                            codex_index=$((codex_index + 1))
                            while [ "$codex_index" -lt "''${#codex_arguments[@]}" ]; do
                              codex_argument="''${codex_arguments[$codex_index]}"
                              case "$codex_argument" in
                                --) break ;;
                                -h | --help | -V | --version)
                                  codex_scan_ok=0
                                  break
                                  ;;
                                --ignore-user-config)
                                  codex_ignore_user_config=1
                                  codex_index=$((codex_index + 1))
                                  continue
                                  ;;
                                -p | --profile | --profile=* | -p=* | -p?*)
                                  codex_route=delegate
                                  break
                                  ;;
                                *)
                                  codex_index=$((codex_index + 1))
                                  ;;
                              esac
                            done
                            break
                            ;;
                        esac
                        codex_index=$((codex_index + 1))
                        continue
                        ;;
                    esac
                  done
                  ;;
                resume | fork | archive | delete | unarchive)
                  codex_route=manage
                  codex_index=$((codex_command_index + 1))
                  while [ "$codex_index" -lt "''${#codex_arguments[@]}" ]; do
                    codex_argument="''${codex_arguments[$codex_index]}"
                    case "$codex_argument" in
                      --) break ;;
                      -h | --help | -V | --version)
                        codex_scan_ok=0
                        break
                        ;;
                      -p | --profile | --profile=* | -p=* | -p?*)
                        codex_profile_scope=local
                        if ! codex_scan_profile_at; then
                          codex_scan_ok=0
                          break
                        fi
                        continue
                        ;;
                      -i | --image)
                        codex_index=$((codex_index + 1))
                        codex_image_count=0
                        while [ "$codex_index" -lt "''${#codex_arguments[@]}" ]; do
                          codex_option_value="''${codex_arguments[$codex_index]}"
                          case "$codex_option_value" in
                            -) ;;
                            -*) break ;;
                          esac
                          codex_image_count=$((codex_image_count + 1))
                          codex_index=$((codex_index + 1))
                        done
                        if [ "$codex_image_count" -eq 0 ]; then
                          codex_scan_ok=0
                          break
                        fi
                        continue
                        ;;
                      -c | --config | --enable | --disable | --remote | \
                      --remote-auth-token-env | -m | --model | \
                      --local-provider | -s | --sandbox | -C | --cd | \
                      --add-dir | -a | --ask-for-approval)
                        if [ $((codex_index + 1)) -ge "''${#codex_arguments[@]}" ]; then
                          codex_scan_ok=0
                          break
                        fi
                        codex_option_value="''${codex_arguments[$((codex_index + 1))]}"
                        case "$codex_option_value" in
                          -) ;;
                          -*)
                            codex_scan_ok=0
                            break
                            ;;
                        esac
                        [ "$codex_scan_ok" -eq 1 ] || break
                        codex_index=$((codex_index + 2))
                        continue
                        ;;
                      --config=* | -c?* | --enable=* | --disable=* | \
                      --remote=* | --remote-auth-token-env=* | \
                      --image=* | -i?* | --model=* | -m?* | \
                      --local-provider=* | --sandbox=* | -s?* | --cd=* | \
                      -C?* | --add-dir=* | --strict-config | --oss | \
                      --dangerously-bypass-approvals-and-sandbox | --yolo | \
                      --dangerously-bypass-hook-trust | \
                      --ask-for-approval=* | -a?* | --search | --no-alt-screen | \
                      --last | --all | --include-non-interactive | --force)
                        codex_index=$((codex_index + 1))
                        continue
                        ;;
                      -?*)
                        codex_scan_ok=0
                        break
                        ;;
                      *)
                        codex_index=$((codex_index + 1))
                        ;;
                    esac
                  done
                  ;;
                sandbox)
                  codex_route=manage
                  codex_index=$((codex_command_index + 1))
                  while [ "$codex_index" -lt "''${#codex_arguments[@]}" ]; do
                    codex_argument="''${codex_arguments[$codex_index]}"
                    case "$codex_argument" in
                      --) break ;;
                      -h | --help | -V | --version)
                        codex_scan_ok=0
                        break
                        ;;
                      -p | --profile | --profile=* | -p=* | -p?*)
                        codex_profile_scope=local
                        if ! codex_scan_profile_at; then
                          codex_scan_ok=0
                          break
                        fi
                        continue
                        ;;
                      --sandbox-state-json | --sandbox-state-readable-root | \
                      --permission-profile | --permissions-profile | -P | \
                      -C | --cd | -c | --config | --enable | \
                      --disable${codexSandboxDarwinValueCase})
                        if [ $((codex_index + 1)) -ge "''${#codex_arguments[@]}" ]; then
                          codex_scan_ok=0
                          break
                        fi
                        codex_option_value="''${codex_arguments[$((codex_index + 1))]}"
                        case "$codex_option_value" in
                          -) ;;
                          -*)
                            codex_scan_ok=0
                            break
                            ;;
                        esac
                        [ "$codex_scan_ok" -eq 1 ] || break
                        codex_index=$((codex_index + 2))
                        continue
                        ;;
                      --sandbox-state-json=* | \
                      --sandbox-state-readable-root=* | \
                      --permission-profile=* | --permissions-profile=* | \
                      -P?* | -C?* | --cd=* | --config=* | -c?* | \
                      --enable=* | --disable=*${codexSandboxDarwinAttachedCase} | \
                      --sandbox-state-disable-network | \
                      --include-managed-config${codexSandboxDarwinFlagCase})
                        codex_index=$((codex_index + 1))
                        continue
                        ;;
                      -)
                        break
                        ;;
                      -*)
                        codex_scan_ok=0
                        break
                        ;;
                      *)
                        break
                        ;;
                    esac
                  done
                  ;;
                review)
                  codex_route=manage
                  codex_index=$((codex_command_index + 1))
                  while [ "$codex_index" -lt "''${#codex_arguments[@]}" ]; do
                    codex_argument="''${codex_arguments[$codex_index]}"
                    case "$codex_argument" in
                      --) break ;;
                      -h | --help | -V | --version)
                        codex_scan_ok=0
                        break
                        ;;
                      *)
                        codex_index=$((codex_index + 1))
                        ;;
                    esac
                  done
                  ;;
                mcp)
                  codex_route=manage
                  codex_mcp_command=
                  codex_mcp_name_seen=0
                  codex_index=$((codex_command_index + 1))
                  while [ "$codex_index" -lt "''${#codex_arguments[@]}" ]; do
                    codex_argument="''${codex_arguments[$codex_index]}"
                    case "$codex_argument" in
                      --)
                        break
                        ;;
                      -h | --help | -V | --version)
                        codex_scan_ok=0
                        break
                        ;;
                      -c | --config | --enable | --disable | --env | --url | \
                      --bearer-token-env-var | --oauth-client-id | \
                      --oauth-resource | --scopes)
                        if [ $((codex_index + 1)) -ge "''${#codex_arguments[@]}" ]; then
                          codex_scan_ok=0
                          break
                        fi
                        codex_option_value="''${codex_arguments[$((codex_index + 1))]}"
                        case "$codex_option_value" in
                          -) ;;
                          -*)
                            codex_scan_ok=0
                            break
                            ;;
                        esac
                        [ "$codex_scan_ok" -eq 1 ] || break
                        codex_index=$((codex_index + 2))
                        continue
                        ;;
                      --config=* | -c?* | --enable=* | --disable=* | \
                      --env=* | --url=* | --bearer-token-env-var=* | \
                      --oauth-client-id=* | --oauth-resource=* | --scopes=* | \
                      --json)
                        codex_index=$((codex_index + 1))
                        continue
                        ;;
                      -?*)
                        if [ "$codex_mcp_command" = add ] \
                          && [ "$codex_mcp_name_seen" -eq 1 ]; then
                          break
                        fi
                        codex_scan_ok=0
                        break
                        ;;
                      *)
                        if [ -z "$codex_mcp_command" ]; then
                          if [ "$codex_argument" = help ]; then
                            codex_scan_ok=0
                            break
                          fi
                          codex_mcp_command="$codex_argument"
                          codex_index=$((codex_index + 1))
                          continue
                        fi
                        if [ "$codex_mcp_command" = add ]; then
                          if [ "$codex_mcp_name_seen" -eq 0 ]; then
                            codex_mcp_name_seen=1
                            codex_index=$((codex_index + 1))
                            continue
                          fi
                          # Add's first remaining positional starts the stdio
                          # command payload; all later option-looking text belongs
                          # to that command, including --help and -p.
                          break
                        fi
                        codex_index=$((codex_index + 1))
                        ;;
                    esac
                  done
                  ;;
                debug)
                  codex_index=$((codex_command_index + 1))
                  while [ "$codex_index" -lt "''${#codex_arguments[@]}" ]; do
                    codex_argument="''${codex_arguments[$codex_index]}"
                    case "$codex_argument" in
                      -c | --config | --enable | --disable)
                        if [ $((codex_index + 1)) -ge "''${#codex_arguments[@]}" ]; then
                          codex_scan_ok=0
                          break
                        fi
                        codex_option_value="''${codex_arguments[$((codex_index + 1))]}"
                        case "$codex_option_value" in
                          -) ;;
                          -*)
                            codex_scan_ok=0
                            break
                            ;;
                        esac
                        [ "$codex_scan_ok" -eq 1 ] || break
                        codex_index=$((codex_index + 2))
                        continue
                        ;;
                      --config=* | -c?* | --enable=* | --disable=*)
                        codex_index=$((codex_index + 1))
                        continue
                        ;;
                      prompt-input)
                        codex_route=manage
                        codex_index=$((codex_index + 1))
                        while [ "$codex_index" -lt "''${#codex_arguments[@]}" ]; do
                          codex_argument="''${codex_arguments[$codex_index]}"
                          case "$codex_argument" in
                            --) break ;;
                            -h | --help | -V | --version)
                              codex_scan_ok=0
                              break
                              ;;
                            *)
                              codex_index=$((codex_index + 1))
                              ;;
                          esac
                        done
                        break
                        ;;
                      *)
                        codex_route=delegate
                        break
                        ;;
                    esac
                  done
                  ;;
                *)
                  codex_route=delegate
                  ;;
              esac
            fi
          fi

          if [ "$codex_scan_ok" -ne 1 ]; then
            codex_route=delegate
          fi
          if [ "$codex_route" = manage ] \
            && [ "$codex_ignore_user_config" -eq 1 ]; then
            printf '%s\n' \
              'codex: managed configuration conflicts with --ignore-user-config' >&2
            exit 2
          fi
          if [ "$codex_route" = manage ]; then
            if [ "$codex_root_profiles" -gt 1 ] \
              || [ "$codex_local_profiles" -gt 1 ]; then
              codex_route=delegate
            elif [ $((codex_root_profiles + codex_local_profiles)) -gt 0 ]; then
              codex_route=conflict
            fi
          fi

          case "$codex_route" in
            conflict)
              printf '%s\n' \
                'codex: managed configuration conflicts with a caller profile' >&2
              exit 2
              ;;
            manage)
              codex_prepare_runtime_profile
              codex_import_legacy_ref_api_key
              exec -a codex @codex_unwrapped@ --profile nix-runtime "$@"
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
  meta = package.meta or { };
}
