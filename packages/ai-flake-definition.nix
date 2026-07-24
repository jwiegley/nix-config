inputs@{
  nixpkgs,
  llm-agents,
  git-ai,
  ...
}:
let
  systems = [
    "aarch64-darwin"
    "aarch64-linux"
    "x86_64-linux"
  ];

  inherit (nixpkgs) lib;

  forAllSystems = lib.genAttrs systems;

  overlays = import ../overlays/ai { inherit inputs; };

  mkPkgs =
    system:
    import nixpkgs {
      inherit system overlays;
      config.allowUnfree = true;
    };

  optPkg =
    pkgs: name:
    if pkgs ? ${name} && pkgs.lib.meta.availableOn pkgs.stdenv.hostPlatform pkgs.${name} then
      [ pkgs.${name} ]
    else
      [ ];

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

  patchAgentPackage =
    pkgs: name: package:
    if name == "claude-code" then
      let
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
    else if name == "codex" then
      assert (package.version or null) == "0.144.6";
      let
        codexAppCommandCase = pkgs.lib.optionalString pkgs.stdenv.isDarwin " | app";
        codexSandboxDarwinValueCase = pkgs.lib.optionalString pkgs.stdenv.isDarwin " | --allow-unix-socket";
        codexSandboxDarwinAttachedCase = pkgs.lib.optionalString pkgs.stdenv.isDarwin " | --allow-unix-socket=?*";
        codexSandboxDarwinEmptyCase = pkgs.lib.optionalString pkgs.stdenv.isDarwin " | --allow-unix-socket=";
        codexSandboxDarwinFlagCase = pkgs.lib.optionalString pkgs.stdenv.isDarwin " | --log-denials";
        codexWrapper = pkgs.writeShellScript "codex" ''
          set -euo pipefail
          umask 077

          # $HOME (and so ~/.codex) is shared over NFS across hosts.
          # Concurrent cross-host writers corrupt SQLite databases, so
          # keep CODEX_HOME shared and move only the conflict-prone
          # state -- the SQLite databases and the fixed-name tui log --
          # to machine-local disk.  Everything else (config, auth,
          # sessions, history, prompts) stays shared.
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

          # One-time seed per host: carry accumulated memories from the
          # shared home into this host's local databases.  The mkdir is
          # an atomic mutex so concurrent first runs seed at most once,
          # and the temp-copy + no-clobber mv means no codex ever
          # observes a partially copied file.  The mutex is released
          # after every attempt: the file-existence guard prevents
          # steady-state re-seeding, while a transiently failed copy
          # (NFS stall) can retry on the next launch.  Only the main DB
          # file is copied: it is self-consistent as of its last
          # checkpoint, whereas a -wal/-shm trio copied from a live NFS
          # database can be mutually inconsistent.  (A torn copy of a
          # concurrently-written main file is possible during the
          # transition window; codex detects and rebuilds a bad DB.)
          # The state DB rebuilds itself from shared rollout files;
          # logs and goals start fresh.
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

          # The tui appends to a fixed-name, lock-free log and unlinks it
          # on startup; cross-host that tears lines and litters .nfs*
          # files.  Point the shared log path at machine-local disk.
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

          codex_profile_name_is_valid() {
            [[ "$1" =~ ^[A-Za-z0-9_-]+$ ]]
          }

          codex_sandbox_value_is_valid() {
            case "$1" in
              read-only | workspace-write | danger-full-access) return 0 ;;
              *) return 1 ;;
            esac
          }

          codex_approval_value_is_valid() {
            case "$1" in
              untrusted | on-request | never) return 0 ;;
              *) return 1 ;;
            esac
          }

          codex_value_looks_like_option() {
            [[ "$1" == -* && "$1" != - ]]
          }

          codex_image_value_is_valid() {
            [ -n "$1" ] || return 1
            case "$1" in
              ,* | *, | *,,*) return 1 ;;
              *) return 0 ;;
            esac
          }

          codex_mark_option_once() {
            local option_key=$1
            case " $codex_seen_options " in
              *" $option_key "*) return 1 ;;
            esac
            codex_seen_options="$codex_seen_options $option_key"
          }

          codex_exec_nested_is_valid() {
            local nested_command=$1
            local nested_index=$2
            local nested_argument nested_image nested_option_key
            local nested_positionals=0
            local nested_bypass=0
            local nested_full_auto=0
            local nested_uncommitted=0
            local nested_base=0
            local nested_commit=0
            local nested_title=0

            codex_seen_options=
            while [ "$nested_index" -lt "''${#codex_arguments[@]}" ]; do
              nested_argument="''${codex_arguments[$nested_index]}"
              nested_option_key=
              case "$nested_argument" in
                -m | --model | -m?* | --model=*) nested_option_key=model ;;
                --dangerously-bypass-approvals-and-sandbox | --yolo)
                  nested_option_key=bypass
                  ;;
                --dangerously-bypass-hook-trust) nested_option_key=hook-trust ;;
                --strict-config) nested_option_key=strict ;;
                --skip-git-repo-check) nested_option_key=skip-git ;;
                --ephemeral) nested_option_key=ephemeral ;;
                --ignore-user-config) nested_option_key=ignore-user-config ;;
                --ignore-rules) nested_option_key=ignore-rules ;;
                --full-auto) nested_option_key=full-auto ;;
                --output-schema | --output-schema=*) nested_option_key=output-schema ;;
                --json | --experimental-json) nested_option_key=json ;;
                -o | --output-last-message | -o?* | --output-last-message=*)
                  nested_option_key=output-last
                  ;;
                --last) nested_option_key=last ;;
                --all) nested_option_key=all ;;
                --uncommitted) nested_option_key=uncommitted ;;
                --base | --base=*) nested_option_key=base ;;
                --commit | --commit=*) nested_option_key=commit ;;
                --title | --title=*) nested_option_key=title ;;
              esac
              if [ -n "$nested_option_key" ] \
                && ! codex_mark_option_once "$nested_option_key"; then
                return 1
              fi

              case "$nested_argument" in
                --)
                  nested_positionals=$((
                    nested_positionals
                    + ''${#codex_arguments[@]}
                    - nested_index
                    - 1
                  ))
                  break
                  ;;
                -h | --help)
                  return 1
                  ;;
                -c | --config | --enable | --disable | -m | --model)
                  if [ $((nested_index + 1)) -ge "''${#codex_arguments[@]}" ] \
                    || codex_value_looks_like_option \
                      "''${codex_arguments[$((nested_index + 1))]}"; then
                    return 1
                  fi
                  nested_index=$((nested_index + 2))
                  continue
                  ;;
                --config=* | -c?* | --enable=* | --disable=* | --model=* | -m?*)
                  nested_index=$((nested_index + 1))
                  continue
                  ;;
                --dangerously-bypass-approvals-and-sandbox | --yolo)
                  nested_bypass=1
                  nested_index=$((nested_index + 1))
                  continue
                  ;;
                --dangerously-bypass-hook-trust | --strict-config | \
                --skip-git-repo-check | --ephemeral | --ignore-user-config | \
                --ignore-rules | --json | --experimental-json)
                  nested_index=$((nested_index + 1))
                  continue
                  ;;
                --full-auto)
                  nested_full_auto=1
                  nested_index=$((nested_index + 1))
                  continue
                  ;;
                --output-schema | -o | --output-last-message)
                  if [ $((nested_index + 1)) -ge "''${#codex_arguments[@]}" ] \
                    || [ -z "''${codex_arguments[$((nested_index + 1))]}" ] \
                    || codex_value_looks_like_option \
                      "''${codex_arguments[$((nested_index + 1))]}"; then
                    return 1
                  fi
                  nested_index=$((nested_index + 2))
                  continue
                  ;;
                --output-schema= | -o= | --output-last-message=)
                  return 1
                  ;;
                --output-schema=?* | -o?* | --output-last-message=?*)
                  nested_index=$((nested_index + 1))
                  continue
                  ;;
              esac

              if [ "$nested_command" = resume ]; then
                case "$nested_argument" in
                  --last | --all)
                    nested_index=$((nested_index + 1))
                    continue
                    ;;
                  -i | --image)
                    if [ $((nested_index + 1)) -ge "''${#codex_arguments[@]}" ] \
                      || [ -z "''${codex_arguments[$((nested_index + 1))]}" ] \
                      || codex_value_looks_like_option \
                        "''${codex_arguments[$((nested_index + 1))]}" \
                      || ! codex_image_value_is_valid \
                        "''${codex_arguments[$((nested_index + 1))]}"; then
                      return 1
                    fi
                    nested_index=$((nested_index + 2))
                    continue
                    ;;
                  --image= | -i=)
                    return 1
                    ;;
                  --image=?* | -i?*)
                    case "$nested_argument" in
                      --image=*) nested_image="''${nested_argument#--image=}" ;;
                      *)
                        nested_image="''${nested_argument#-i}"
                        nested_image="''${nested_image#=}"
                        ;;
                    esac
                    codex_image_value_is_valid "$nested_image" || return 1
                    nested_index=$((nested_index + 1))
                    continue
                    ;;
                esac
              else
                case "$nested_argument" in
                  --uncommitted)
                    nested_uncommitted=1
                    nested_index=$((nested_index + 1))
                    continue
                    ;;
                  --base | --commit | --title)
                    if [ $((nested_index + 1)) -ge "''${#codex_arguments[@]}" ] \
                      || codex_value_looks_like_option \
                        "''${codex_arguments[$((nested_index + 1))]}"; then
                      return 1
                    fi
                    case "$nested_argument" in
                      --base) nested_base=1 ;;
                      --commit) nested_commit=1 ;;
                      --title) nested_title=1 ;;
                    esac
                    nested_index=$((nested_index + 2))
                    continue
                    ;;
                  --base=* | --commit=* | --title=*)
                    case "$nested_argument" in
                      --base=*) nested_base=1 ;;
                      --commit=*) nested_commit=1 ;;
                      --title=*) nested_title=1 ;;
                    esac
                    nested_index=$((nested_index + 1))
                    continue
                    ;;
                esac
              fi

              case "$nested_argument" in
                -?*) return 1 ;;
                *)
                  nested_positionals=$((nested_positionals + 1))
                  nested_index=$((nested_index + 1))
                  ;;
              esac
            done

            if [ "$nested_full_auto" -eq 1 ] && [ "$nested_bypass" -eq 1 ]; then
              return 1
            fi
            if [ "$nested_command" = resume ]; then
              [ "$nested_positionals" -le 2 ] || return 1
            else
              [ "$nested_positionals" -le 1 ] || return 1
              if [ $((nested_uncommitted + nested_base + nested_commit + nested_positionals)) -gt 1 ]; then
                return 1
              fi
              if [ "$nested_title" -eq 1 ] && [ "$nested_commit" -eq 0 ]; then
                return 1
              fi
            fi
            return 0
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
                codex_manage=0
                codex_profile_conflict=0
                codex_root_profile_seen=0
                codex_root_approval_seen=0
                codex_root_bypass_seen=0
                codex_root_model_seen=0
                codex_root_local_provider_seen=0
                codex_root_sandbox_seen=0
                codex_root_cd_seen=0
                codex_root_remote_seen=0
                codex_root_remote_auth_seen=0
                codex_root_oss_seen=0
                codex_root_hook_trust_seen=0
                codex_root_search_seen=0
                codex_root_no_alt_screen_seen=0
                codex_root_strict_seen=0
                codex_child_remote_seen=0
                codex_child_remote_auth_seen=0
                codex_command=
                codex_command_index=-1
                codex_prompt_command=0
                codex_recognized=1
                codex_arguments=("$@")
                codex_index=0

                while [ "$codex_index" -lt "''${#codex_arguments[@]}" ]; do
                  codex_argument="''${codex_arguments[$codex_index]}"
                  case "$codex_argument" in
                    -a | --ask-for-approval | -a?* | --ask-for-approval=*)
                      codex_root_approval_seen=$((codex_root_approval_seen + 1))
                      ;;
                    --dangerously-bypass-approvals-and-sandbox | --yolo)
                      codex_root_bypass_seen=$((codex_root_bypass_seen + 1))
                      ;;
                    -m | --model | -m?* | --model=*)
                      codex_root_model_seen=$((codex_root_model_seen + 1))
                      ;;
                    --local-provider | --local-provider=*)
                      codex_root_local_provider_seen=$((codex_root_local_provider_seen + 1))
                      ;;
                    -s | --sandbox | -s?* | --sandbox=*)
                      codex_root_sandbox_seen=$((codex_root_sandbox_seen + 1))
                      ;;
                    -C | --cd | -C?* | --cd=*)
                      codex_root_cd_seen=$((codex_root_cd_seen + 1))
                      ;;
                    --remote | --remote=*)
                      codex_root_remote_seen=$((codex_root_remote_seen + 1))
                      ;;
                    --remote-auth-token-env | --remote-auth-token-env=*)
                      codex_root_remote_auth_seen=$((codex_root_remote_auth_seen + 1))
                      ;;
                    --oss) codex_root_oss_seen=$((codex_root_oss_seen + 1)) ;;
                    --dangerously-bypass-hook-trust)
                      codex_root_hook_trust_seen=$((codex_root_hook_trust_seen + 1))
                      ;;
                    --search) codex_root_search_seen=$((codex_root_search_seen + 1)) ;;
                    --no-alt-screen)
                      codex_root_no_alt_screen_seen=$((codex_root_no_alt_screen_seen + 1))
                      ;;
                    --strict-config)
                      codex_root_strict_seen=$((codex_root_strict_seen + 1))
                      ;;
                    -p | --profile | -p?* | --profile=*)
                      codex_root_profile_seen=$((codex_root_profile_seen + 1))
                      ;;
                  esac
                  if [ "$codex_root_approval_seen" -gt 1 ] \
                    || [ "$codex_root_bypass_seen" -gt 1 ] \
                    || [ "$codex_root_model_seen" -gt 1 ] \
                    || [ "$codex_root_local_provider_seen" -gt 1 ] \
                    || [ "$codex_root_sandbox_seen" -gt 1 ] \
                    || [ "$codex_root_cd_seen" -gt 1 ] \
                    || [ "$codex_root_remote_seen" -gt 1 ] \
                    || [ "$codex_root_remote_auth_seen" -gt 1 ] \
                    || [ "$codex_root_oss_seen" -gt 1 ] \
                    || [ "$codex_root_hook_trust_seen" -gt 1 ] \
                    || [ "$codex_root_search_seen" -gt 1 ] \
                    || [ "$codex_root_no_alt_screen_seen" -gt 1 ] \
                    || [ "$codex_root_strict_seen" -gt 1 ] \
                    || [ "$codex_root_profile_seen" -gt 1 ]; then
                    codex_recognized=0
                    break
                  fi
                  case "$codex_argument" in
                    --)
                      codex_remaining_positionals=$((''${#codex_arguments[@]} - codex_index - 1))
                      if [ $((codex_prompt_command + codex_remaining_positionals)) -gt 1 ]; then
                        codex_recognized=0
                      else
                        codex_manage=1
                      fi
                      break
                      ;;
                    -h | --help | -V | --version)
                      codex_recognized=0
                      break
                      ;;
                    -c | --config | -m | --model | --local-provider | --remote | \
                    --remote-auth-token-env | --enable | --disable)
                      if [ $((codex_index + 1)) -ge "''${#codex_arguments[@]}" ] \
                        || codex_value_looks_like_option \
                          "''${codex_arguments[$((codex_index + 1))]}"; then
                        codex_recognized=0
                        break
                      fi
                      codex_index=$((codex_index + 2))
                      continue
                      ;;
                    -C | --cd | --add-dir)
                      if [ $((codex_index + 1)) -ge "''${#codex_arguments[@]}" ] \
                        || [ -z "''${codex_arguments[$((codex_index + 1))]}" ] \
                        || codex_value_looks_like_option \
                          "''${codex_arguments[$((codex_index + 1))]}"; then
                        codex_recognized=0
                        break
                      fi
                      codex_index=$((codex_index + 2))
                      continue
                      ;;
                    -s | --sandbox)
                      if [ $((codex_index + 1)) -ge "''${#codex_arguments[@]}" ] \
                        || codex_value_looks_like_option \
                          "''${codex_arguments[$((codex_index + 1))]}" \
                        || ! codex_sandbox_value_is_valid \
                          "''${codex_arguments[$((codex_index + 1))]}"; then
                        codex_recognized=0
                        break
                      fi
                      codex_index=$((codex_index + 2))
                      continue
                      ;;
                    -a | --ask-for-approval)
                      if [ $((codex_index + 1)) -ge "''${#codex_arguments[@]}" ] \
                        || codex_value_looks_like_option \
                          "''${codex_arguments[$((codex_index + 1))]}" \
                        || ! codex_approval_value_is_valid \
                          "''${codex_arguments[$((codex_index + 1))]}"; then
                        codex_recognized=0
                        break
                      fi
                      codex_index=$((codex_index + 2))
                      continue
                      ;;
                    -p | --profile)
                      if [ $((codex_index + 1)) -ge "''${#codex_arguments[@]}" ] \
                        || codex_value_looks_like_option \
                          "''${codex_arguments[$((codex_index + 1))]}" \
                        || ! codex_profile_name_is_valid \
                          "''${codex_arguments[$((codex_index + 1))]}"; then
                        codex_recognized=0
                        break
                      fi
                      codex_profile_conflict=1
                      codex_index=$((codex_index + 2))
                      continue
                      ;;
                    -i | --image)
                      codex_index=$((codex_index + 1))
                      if [ "$codex_index" -ge "''${#codex_arguments[@]}" ] \
                        || [ -z "''${codex_arguments[$codex_index]}" ] \
                        || codex_value_looks_like_option \
                          "''${codex_arguments[$codex_index]}"; then
                        codex_recognized=0
                        break
                      fi
                      while [ "$codex_index" -lt "''${#codex_arguments[@]}" ] \
                        && ! codex_value_looks_like_option \
                          "''${codex_arguments[$codex_index]}"; do
                        if ! codex_image_value_is_valid \
                          "''${codex_arguments[$codex_index]}"; then
                          codex_recognized=0
                          break
                        fi
                        codex_index=$((codex_index + 1))
                      done
                      [ "$codex_recognized" -eq 1 ] || break
                      continue
                      ;;
                    --config= | -c= | --model= | -m= | --local-provider= | \
                    --remote= | --remote-auth-token-env= | --enable= | --disable=)
                      codex_index=$((codex_index + 1))
                      continue
                      ;;
                    --sandbox= | -s= | --cd= | -C= | --add-dir= | \
                    --ask-for-approval= | -a= | --image= | -i=)
                      codex_recognized=0
                      break
                      ;;
                    --sandbox=*)
                      codex_option_value="''${codex_argument#--sandbox=}"
                      if ! codex_sandbox_value_is_valid "$codex_option_value"; then
                        codex_recognized=0
                        break
                      fi
                      codex_index=$((codex_index + 1))
                      continue
                      ;;
                    -s?*)
                      codex_option_value="''${codex_argument#-s}"
                      codex_option_value="''${codex_option_value#=}"
                      if ! codex_sandbox_value_is_valid "$codex_option_value"; then
                        codex_recognized=0
                        break
                      fi
                      codex_index=$((codex_index + 1))
                      continue
                      ;;
                    --ask-for-approval=*)
                      codex_option_value="''${codex_argument#--ask-for-approval=}"
                      if ! codex_approval_value_is_valid "$codex_option_value"; then
                        codex_recognized=0
                        break
                      fi
                      codex_index=$((codex_index + 1))
                      continue
                      ;;
                    -a?*)
                      codex_option_value="''${codex_argument#-a}"
                      codex_option_value="''${codex_option_value#=}"
                      if ! codex_approval_value_is_valid "$codex_option_value"; then
                        codex_recognized=0
                        break
                      fi
                      codex_index=$((codex_index + 1))
                      continue
                      ;;
                    --config=?* | -c?* | --model=?* | -m?* | --local-provider=?*)
                      codex_index=$((codex_index + 1))
                      continue
                      ;;
                    --image=?* | -i?*)
                      case "$codex_argument" in
                        --image=*) codex_image_value="''${codex_argument#--image=}" ;;
                        *)
                          codex_image_value="''${codex_argument#-i}"
                          codex_image_value="''${codex_image_value#=}"
                          ;;
                      esac
                      if ! codex_image_value_is_valid "$codex_image_value"; then
                        codex_recognized=0
                        break
                      fi
                      codex_index=$((codex_index + 1))
                      continue
                      ;;
                    --cd=?* | -C?* | --add-dir=?* | --remote=?* | \
                    --remote-auth-token-env=?* | --enable=?* | --disable=?*)
                      codex_index=$((codex_index + 1))
                      continue
                      ;;
                    --profile=*)
                      codex_profile_value="''${codex_argument#--profile=}"
                      if ! codex_profile_name_is_valid "$codex_profile_value"; then
                        codex_recognized=0
                        break
                      fi
                      codex_profile_conflict=1
                      codex_index=$((codex_index + 1))
                      continue
                      ;;
                    -p=*)
                      codex_profile_value="''${codex_argument#-p=}"
                      if ! codex_profile_name_is_valid "$codex_profile_value"; then
                        codex_recognized=0
                        break
                      fi
                      codex_profile_conflict=1
                      codex_index=$((codex_index + 1))
                      continue
                      ;;
                    -p?*)
                      codex_profile_value="''${codex_argument#-p}"
                      if ! codex_profile_name_is_valid "$codex_profile_value"; then
                        codex_recognized=0
                        break
                      fi
                      codex_profile_conflict=1
                      codex_index=$((codex_index + 1))
                      continue
                      ;;
                    --oss | --dangerously-bypass-approvals-and-sandbox | --yolo | \
                    --dangerously-bypass-hook-trust | --search | --no-alt-screen | \
                    --strict-config)
                      codex_index=$((codex_index + 1))
                      continue
                      ;;
                    -)
                      if [ "$codex_prompt_command" -eq 1 ]; then
                        codex_recognized=0
                        break
                      fi
                      codex_command="$codex_argument"
                      codex_command_index=$codex_index
                      codex_manage=1
                      codex_prompt_command=1
                      codex_index=$((codex_index + 1))
                      continue
                      ;;
                    -*)
                      codex_recognized=0
                      break
                      ;;
                    *)
                      if [ "$codex_prompt_command" -eq 1 ]; then
                        codex_recognized=0
                        break
                      fi
                      codex_command="$codex_argument"
                      codex_command_index=$codex_index
                      case "$codex_command" in
                        exec | e | review | resume | archive | delete | unarchive | fork | sandbox)
                          codex_manage=1
                          ;;
                        debug)
                          codex_debug_index=$((codex_index + 1))
                          codex_debug_command_index=-1
                          while [ "$codex_debug_index" -lt "''${#codex_arguments[@]}" ]; do
                            codex_debug_argument="''${codex_arguments[$codex_debug_index]}"
                            case "$codex_debug_argument" in
                              -c | --config | --enable | --disable)
                                if [ $((codex_debug_index + 1)) -ge "''${#codex_arguments[@]}" ] \
                                  || codex_value_looks_like_option \
                                    "''${codex_arguments[$((codex_debug_index + 1))]}"; then
                                  codex_recognized=0
                                  break
                                fi
                                codex_debug_index=$((codex_debug_index + 2))
                                ;;
                              --config=* | -c?* | --enable=* | --disable=*)
                                codex_debug_index=$((codex_debug_index + 1))
                                ;;
                              prompt-input)
                                codex_manage=1
                                codex_debug_command_index=$codex_debug_index
                                break
                                ;;
                              *) break ;;
                            esac
                          done
                          ;;
                        login | logout | mcp | plugin | mcp-server | app-server | \
                        remote-control${codexAppCommandCase} | completion | update | doctor | execpolicy | \
                        apply | a | cloud | cloud-tasks | responses-api-proxy | \
                        stdio-to-uds | exec-server | features | help)
                          ;;
                        *)
                          codex_manage=1
                          codex_prompt_command=1
                          codex_index=$((codex_index + 1))
                          continue
                          ;;
                      esac
                      break
                      ;;
                  esac
                done

                if [ "$codex_root_approval_seen" -eq 1 ] \
                  && [ "$codex_root_bypass_seen" -eq 1 ]; then
                  codex_recognized=0
                fi

                case "$codex_command" in
                  sandbox | debug)
                    [ "$codex_root_strict_seen" -eq 0 ] || codex_recognized=0
                    ;;
                esac
                case "$codex_command" in
                  exec | e | review | sandbox | debug)
                    if [ "$codex_root_remote_seen" -eq 1 ] \
                      || [ "$codex_root_remote_auth_seen" -eq 1 ]; then
                      codex_recognized=0
                    fi
                    ;;
                esac

                if [ "$codex_recognized" -eq 1 ] && [ "$codex_command_index" -eq -1 ] \
                  && [ "$codex_index" -ge "''${#codex_arguments[@]}" ]; then
                  codex_manage=1
                fi

                if [ "$codex_recognized" -eq 1 ] && [ "$codex_manage" -eq 1 ]; then
                  codex_scan_profiles=1
                  codex_generic_command=0
                  codex_scan_index=$((codex_command_index + 1))
                  case "$codex_command" in
                    debug | review) codex_scan_profiles=0 ;;
                    exec | e | resume | archive | delete | unarchive | fork)
                      codex_generic_command=1
                      codex_generic_positionals=0
                      codex_generic_last=0
                      codex_generic_approval_seen=0
                      codex_generic_bypass_seen=0
                      codex_generic_full_auto_seen=0
                      codex_seen_options=
                      ;;
                  esac

                  if [ "$codex_command" = sandbox ]; then
                    codex_sandbox_state_json=0
                    codex_sandbox_readable_root=0
                    codex_sandbox_disable_network=0
                    codex_sandbox_permission_profile=0
                    codex_sandbox_cwd=0
                    codex_sandbox_include_managed=0
                    codex_sandbox_log_denials=0
                    codex_sandbox_profile=0
                  fi

                  if [ "$codex_scan_profiles" -eq 1 ]; then
                    while [ "$codex_scan_index" -lt "''${#codex_arguments[@]}" ]; do
                      codex_argument="''${codex_arguments[$codex_scan_index]}"

                      if [ "$codex_generic_command" -eq 1 ]; then
                        codex_option_key=
                        case "$codex_argument" in
                          -m | --model | -m?* | --model=*) codex_option_key=model ;;
                          --local-provider | --local-provider=*) codex_option_key=local-provider ;;
                          -s | --sandbox | -s?* | --sandbox=*) codex_option_key=sandbox ;;
                          -a | --ask-for-approval | -a?* | --ask-for-approval=*)
                            codex_option_key=approval
                            ;;
                          -C | --cd | -C?* | --cd=*) codex_option_key=cd ;;
                          --remote | --remote=*) codex_option_key=remote ;;
                          --remote-auth-token-env | --remote-auth-token-env=*)
                            codex_option_key=remote-auth
                            ;;
                          -p | --profile | -p?* | --profile=*) codex_option_key=profile ;;
                          --oss) codex_option_key=oss ;;
                          --dangerously-bypass-approvals-and-sandbox | --yolo)
                            codex_option_key=bypass
                            ;;
                          --dangerously-bypass-hook-trust) codex_option_key=hook-trust ;;
                          --strict-config) codex_option_key=strict ;;
                          --color | --color=*) codex_option_key=color ;;
                          --output-schema | --output-schema=*) codex_option_key=output-schema ;;
                          -o | --output-last-message | -o?* | --output-last-message=*)
                            codex_option_key=output-last
                            ;;
                          --last) codex_option_key=last ;;
                          --all) codex_option_key=all ;;
                          --include-non-interactive) codex_option_key=include-non-interactive ;;
                          --search) codex_option_key=search ;;
                          --no-alt-screen) codex_option_key=no-alt-screen ;;
                          --force) codex_option_key=force ;;
                          --skip-git-repo-check) codex_option_key=skip-git ;;
                          --ephemeral) codex_option_key=ephemeral ;;
                          --ignore-user-config) codex_option_key=ignore-user-config ;;
                          --ignore-rules) codex_option_key=ignore-rules ;;
                          --json | --experimental-json) codex_option_key=json ;;
                          --full-auto) codex_option_key=full-auto ;;
                        esac
                        if [ -n "$codex_option_key" ] \
                          && ! codex_mark_option_once "$codex_option_key"; then
                          codex_recognized=0
                          break
                        fi
                        case "$codex_option_key" in
                          remote) codex_child_remote_seen=1 ;;
                          remote-auth) codex_child_remote_auth_seen=1 ;;
                        esac
                        case "$codex_argument" in
                          --)
                            codex_generic_positionals=$((
                              codex_generic_positionals
                              + ''${#codex_arguments[@]}
                              - codex_scan_index
                              - 1
                            ))
                            break
                            ;;
                          -h | --help | -V | --version)
                            codex_recognized=0
                            break
                            ;;
                          -c | --config | --enable | --disable | -m | --model | \
                          --local-provider)
                            if [ $((codex_scan_index + 1)) -ge "''${#codex_arguments[@]}" ] \
                              || codex_value_looks_like_option \
                                "''${codex_arguments[$((codex_scan_index + 1))]}"; then
                              codex_recognized=0
                              break
                            fi
                            codex_scan_index=$((codex_scan_index + 2))
                            continue
                            ;;
                          -C | --cd | --add-dir)
                            if [ $((codex_scan_index + 1)) -ge "''${#codex_arguments[@]}" ] \
                              || [ -z "''${codex_arguments[$((codex_scan_index + 1))]}" ] \
                              || codex_value_looks_like_option \
                                "''${codex_arguments[$((codex_scan_index + 1))]}"; then
                              codex_recognized=0
                              break
                            fi
                            codex_scan_index=$((codex_scan_index + 2))
                            continue
                            ;;
                          --remote | --remote-auth-token-env)
                            case "$codex_command" in
                              exec | e)
                                codex_recognized=0
                                break
                                ;;
                            esac
                            if [ $((codex_scan_index + 1)) -ge "''${#codex_arguments[@]}" ] \
                              || codex_value_looks_like_option \
                                "''${codex_arguments[$((codex_scan_index + 1))]}"; then
                              codex_recognized=0
                              break
                            fi
                            codex_scan_index=$((codex_scan_index + 2))
                            continue
                            ;;
                          -s | --sandbox)
                            if [ $((codex_scan_index + 1)) -ge "''${#codex_arguments[@]}" ] \
                              || ! codex_sandbox_value_is_valid \
                                "''${codex_arguments[$((codex_scan_index + 1))]}"; then
                              codex_recognized=0
                              break
                            fi
                            codex_scan_index=$((codex_scan_index + 2))
                            continue
                            ;;
                          -a | --ask-for-approval)
                            case "$codex_command" in
                              resume | fork) ;;
                              *)
                                codex_recognized=0
                                break
                                ;;
                            esac
                            if [ $((codex_scan_index + 1)) -ge "''${#codex_arguments[@]}" ] \
                              || ! codex_approval_value_is_valid \
                                "''${codex_arguments[$((codex_scan_index + 1))]}"; then
                              codex_recognized=0
                              break
                            fi
                            codex_generic_approval_seen=1
                            codex_scan_index=$((codex_scan_index + 2))
                            continue
                            ;;
                          -p | --profile)
                            if [ $((codex_scan_index + 1)) -ge "''${#codex_arguments[@]}" ] \
                              || codex_value_looks_like_option \
                                "''${codex_arguments[$((codex_scan_index + 1))]}" \
                              || ! codex_profile_name_is_valid \
                                "''${codex_arguments[$((codex_scan_index + 1))]}"; then
                              codex_recognized=0
                              break
                            fi
                            codex_profile_conflict=1
                            codex_scan_index=$((codex_scan_index + 2))
                            continue
                            ;;
                          -i | --image)
                            codex_scan_index=$((codex_scan_index + 1))
                            if [ "$codex_scan_index" -ge "''${#codex_arguments[@]}" ] \
                              || [ -z "''${codex_arguments[$codex_scan_index]}" ] \
                              || codex_value_looks_like_option \
                                "''${codex_arguments[$codex_scan_index]}"; then
                              codex_recognized=0
                              break
                            fi
                            while [ "$codex_scan_index" -lt "''${#codex_arguments[@]}" ] \
                              && ! codex_value_looks_like_option \
                                "''${codex_arguments[$codex_scan_index]}"; do
                              if ! codex_image_value_is_valid \
                                "''${codex_arguments[$codex_scan_index]}"; then
                                codex_recognized=0
                                break
                              fi
                              codex_scan_index=$((codex_scan_index + 1))
                            done
                            [ "$codex_recognized" -eq 1 ] || break
                            continue
                            ;;
                          --color | --output-schema | -o | --output-last-message)
                            case "$codex_command" in
                              exec | e) ;;
                              *)
                                codex_recognized=0
                                break
                                ;;
                            esac
                            if [ $((codex_scan_index + 1)) -ge "''${#codex_arguments[@]}" ] \
                              || [ -z "''${codex_arguments[$((codex_scan_index + 1))]}" ] \
                              || codex_value_looks_like_option \
                                "''${codex_arguments[$((codex_scan_index + 1))]}"; then
                              codex_recognized=0
                              break
                            fi
                            if [ "$codex_argument" = --color ]; then
                              case "''${codex_arguments[$((codex_scan_index + 1))]}" in
                                always | never | auto) ;;
                                *)
                                  codex_recognized=0
                                  break
                                  ;;
                              esac
                            fi
                            codex_scan_index=$((codex_scan_index + 2))
                            continue
                            ;;
                          --config=* | -c?* | --enable=* | --disable=* | \
                          --model=* | -m?* | --local-provider=*)
                            codex_scan_index=$((codex_scan_index + 1))
                            continue
                            ;;
                          --cd= | -C= | --add-dir= | --image= | -i=)
                            codex_recognized=0
                            break
                            ;;
                          --image=?* | -i?*)
                            case "$codex_argument" in
                              --image=*) codex_image_value="''${codex_argument#--image=}" ;;
                              *)
                                codex_image_value="''${codex_argument#-i}"
                                codex_image_value="''${codex_image_value#=}"
                                ;;
                            esac
                            if ! codex_image_value_is_valid "$codex_image_value"; then
                              codex_recognized=0
                              break
                            fi
                            codex_scan_index=$((codex_scan_index + 1))
                            continue
                            ;;
                          --cd=?* | -C?* | --add-dir=?*)
                            codex_scan_index=$((codex_scan_index + 1))
                            continue
                            ;;
                          --remote=* | --remote-auth-token-env=*)
                            case "$codex_command" in
                              exec | e) codex_recognized=0 ;;
                            esac
                            codex_scan_index=$((codex_scan_index + 1))
                            continue
                            ;;
                          --sandbox=*)
                            codex_option_value="''${codex_argument#--sandbox=}"
                            if ! codex_sandbox_value_is_valid "$codex_option_value"; then
                              codex_recognized=0
                              break
                            fi
                            codex_scan_index=$((codex_scan_index + 1))
                            continue
                            ;;
                          -s?*)
                            codex_option_value="''${codex_argument#-s}"
                            codex_option_value="''${codex_option_value#=}"
                            if ! codex_sandbox_value_is_valid "$codex_option_value"; then
                              codex_recognized=0
                              break
                            fi
                            codex_scan_index=$((codex_scan_index + 1))
                            continue
                            ;;
                          --ask-for-approval=* | -a?*)
                            case "$codex_command" in
                              resume | fork) ;;
                              *)
                                codex_recognized=0
                                break
                                ;;
                            esac
                            case "$codex_argument" in
                              --ask-for-approval=*)
                                codex_option_value="''${codex_argument#--ask-for-approval=}"
                                ;;
                              *)
                                codex_option_value="''${codex_argument#-a}"
                                codex_option_value="''${codex_option_value#=}"
                                ;;
                            esac
                            if ! codex_approval_value_is_valid "$codex_option_value"; then
                              codex_recognized=0
                              break
                            fi
                            codex_generic_approval_seen=1
                            codex_scan_index=$((codex_scan_index + 1))
                            continue
                            ;;
                          --profile=* | -p=* | -p?*)
                            case "$codex_argument" in
                              --profile=*) codex_profile_value="''${codex_argument#--profile=}" ;;
                              -p=*) codex_profile_value="''${codex_argument#-p=}" ;;
                              *) codex_profile_value="''${codex_argument#-p}" ;;
                            esac
                            if ! codex_profile_name_is_valid "$codex_profile_value"; then
                              codex_recognized=0
                              break
                            fi
                            codex_profile_conflict=1
                            codex_scan_index=$((codex_scan_index + 1))
                            continue
                            ;;
                          --color=*)
                            case "$codex_command:$codex_argument" in
                              exec:--color=always | exec:--color=never | exec:--color=auto | \
                              e:--color=always | e:--color=never | e:--color=auto) ;;
                              *) codex_recognized=0 ;;
                            esac
                            codex_scan_index=$((codex_scan_index + 1))
                            continue
                            ;;
                          --output-schema= | -o= | --output-last-message=)
                            codex_recognized=0
                            break
                            ;;
                          --output-schema=?* | -o?* | --output-last-message=?*)
                            case "$codex_command" in
                              exec | e) ;;
                              *) codex_recognized=0 ;;
                            esac
                            codex_scan_index=$((codex_scan_index + 1))
                            continue
                            ;;
                          --oss | --dangerously-bypass-hook-trust | --strict-config)
                            codex_scan_index=$((codex_scan_index + 1))
                            continue
                            ;;
                          --dangerously-bypass-approvals-and-sandbox | --yolo)
                            codex_generic_bypass_seen=1
                            codex_scan_index=$((codex_scan_index + 1))
                            continue
                            ;;
                          --last | --all)
                            case "$codex_command" in
                              resume | fork)
                                [ "$codex_argument" != --last ] || codex_generic_last=1
                                ;;
                              *) codex_recognized=0 ;;
                            esac
                            codex_scan_index=$((codex_scan_index + 1))
                            continue
                            ;;
                          --include-non-interactive)
                            [ "$codex_command" = resume ] || codex_recognized=0
                            codex_scan_index=$((codex_scan_index + 1))
                            continue
                            ;;
                          --search | --no-alt-screen)
                            case "$codex_command" in
                              resume | fork) ;;
                              *) codex_recognized=0 ;;
                            esac
                            codex_scan_index=$((codex_scan_index + 1))
                            continue
                            ;;
                          --force)
                            [ "$codex_command" = delete ] || codex_recognized=0
                            codex_scan_index=$((codex_scan_index + 1))
                            continue
                            ;;
                          --skip-git-repo-check | --ephemeral | --ignore-user-config | \
                          --ignore-rules | --json | --experimental-json)
                            case "$codex_command" in
                              exec | e) ;;
                              *) codex_recognized=0 ;;
                            esac
                            codex_scan_index=$((codex_scan_index + 1))
                            continue
                            ;;
                          --full-auto)
                            case "$codex_command" in
                              exec | e) codex_generic_full_auto_seen=1 ;;
                              *) codex_recognized=0 ;;
                            esac
                            codex_scan_index=$((codex_scan_index + 1))
                            continue
                            ;;
                          -)
                            codex_generic_positionals=$((codex_generic_positionals + 1))
                            codex_scan_index=$((codex_scan_index + 1))
                            continue
                            ;;
                          -*)
                            codex_recognized=0
                            break
                            ;;
                          *)
                            if { [ "$codex_command" = exec ] \
                              || [ "$codex_command" = e ]; } \
                              && [ "$codex_generic_positionals" -eq 0 ]; then
                              case "$codex_argument" in
                                help)
                                  codex_recognized=0
                                  break
                                  ;;
                                resume | review)
                                  if ! codex_exec_nested_is_valid "$codex_argument" \
                                    $((codex_scan_index + 1)); then
                                    codex_recognized=0
                                  fi
                                  codex_scan_index="''${#codex_arguments[@]}"
                                  break
                                  ;;
                              esac
                            fi
                            codex_generic_positionals=$((codex_generic_positionals + 1))
                            codex_scan_index=$((codex_scan_index + 1))
                            continue
                            ;;
                        esac
                      fi

                      [ "$codex_argument" != -- ] || break

                      if [ "$codex_command" = sandbox ]; then
                        if [ "$codex_argument" = --log-denials ]; then
                          codex_sandbox_log_denials=$((codex_sandbox_log_denials + 1))
                        fi
                        case "$codex_argument" in
                          --sandbox-state-json | --sandbox-state-json=*)
                            codex_sandbox_state_json=$((codex_sandbox_state_json + 1))
                            ;;
                          --sandbox-state-readable-root | --sandbox-state-readable-root=*)
                            codex_sandbox_readable_root=1
                            ;;
                          --sandbox-state-disable-network)
                            codex_sandbox_disable_network=$((codex_sandbox_disable_network + 1))
                            ;;
                          --permission-profile | --permissions-profile | -P | \
                          --permission-profile=* | --permissions-profile=* | -P?*)
                            codex_sandbox_permission_profile=$((codex_sandbox_permission_profile + 1))
                            ;;
                          -C | --cd | -C?* | --cd=*)
                            codex_sandbox_cwd=$((codex_sandbox_cwd + 1))
                            ;;
                          --include-managed-config)
                            codex_sandbox_include_managed=$((codex_sandbox_include_managed + 1))
                            ;;
                        esac
                      fi

                      case "$codex_argument" in
                        -p | --profile)
                          if [ "$codex_command" = sandbox ]; then
                            codex_sandbox_profile=$((codex_sandbox_profile + 1))
                            if [ "$codex_sandbox_profile" -gt 1 ]; then
                              codex_recognized=0
                              break
                            fi
                          fi
                          if [ $((codex_scan_index + 1)) -ge "''${#codex_arguments[@]}" ] \
                            || codex_value_looks_like_option \
                              "''${codex_arguments[$((codex_scan_index + 1))]}" \
                            || ! codex_profile_name_is_valid \
                              "''${codex_arguments[$((codex_scan_index + 1))]}"; then
                            codex_recognized=0
                            break
                          fi
                          codex_profile_conflict=1
                          if [ "$codex_command" = sandbox ]; then
                            codex_scan_index=$((codex_scan_index + 2))
                            continue
                          fi
                          ;;
                        --profile=*)
                          if [ "$codex_command" = sandbox ]; then
                            codex_sandbox_profile=$((codex_sandbox_profile + 1))
                            if [ "$codex_sandbox_profile" -gt 1 ]; then
                              codex_recognized=0
                              break
                            fi
                          fi
                          codex_profile_value="''${codex_argument#--profile=}"
                          if ! codex_profile_name_is_valid "$codex_profile_value"; then
                            codex_recognized=0
                            break
                          fi
                          codex_profile_conflict=1
                          if [ "$codex_command" = sandbox ]; then
                            codex_scan_index=$((codex_scan_index + 1))
                            continue
                          fi
                          ;;
                        -p=*)
                          if [ "$codex_command" = sandbox ]; then
                            codex_sandbox_profile=$((codex_sandbox_profile + 1))
                            if [ "$codex_sandbox_profile" -gt 1 ]; then
                              codex_recognized=0
                              break
                            fi
                          fi
                          codex_profile_value="''${codex_argument#-p=}"
                          if ! codex_profile_name_is_valid "$codex_profile_value"; then
                            codex_recognized=0
                            break
                          fi
                          codex_profile_conflict=1
                          if [ "$codex_command" = sandbox ]; then
                            codex_scan_index=$((codex_scan_index + 1))
                            continue
                          fi
                          ;;
                        -p?*)
                          if [ "$codex_command" = sandbox ]; then
                            codex_sandbox_profile=$((codex_sandbox_profile + 1))
                            if [ "$codex_sandbox_profile" -gt 1 ]; then
                              codex_recognized=0
                              break
                            fi
                          fi
                          codex_profile_value="''${codex_argument#-p}"
                          if ! codex_profile_name_is_valid "$codex_profile_value"; then
                            codex_recognized=0
                            break
                          fi
                          codex_profile_conflict=1
                          if [ "$codex_command" = sandbox ]; then
                            codex_scan_index=$((codex_scan_index + 1))
                            continue
                          fi
                          ;;
                      esac

                      if [ "$codex_command" = sandbox ]; then
                        case "$codex_argument" in
                          -p | --profile | --profile=* | -p=* | -p?*) ;;
                          --sandbox-state-json | --sandbox-state-readable-root | \
                          --permission-profile | --permissions-profile | -P | \
                          -c | --config | --enable | --disable${codexSandboxDarwinValueCase})
                            if [ $((codex_scan_index + 1)) -ge "''${#codex_arguments[@]}" ] \
                              || codex_value_looks_like_option \
                                "''${codex_arguments[$((codex_scan_index + 1))]}"; then
                              codex_recognized=0
                              break
                            fi
                            codex_scan_index=$((codex_scan_index + 2))
                            continue
                            ;;
                          -C | --cd)
                            if [ $((codex_scan_index + 1)) -ge "''${#codex_arguments[@]}" ] \
                              || [ -z "''${codex_arguments[$((codex_scan_index + 1))]}" ] \
                              || codex_value_looks_like_option \
                                "''${codex_arguments[$((codex_scan_index + 1))]}"; then
                              codex_recognized=0
                              break
                            fi
                            codex_scan_index=$((codex_scan_index + 2))
                            continue
                            ;;
                          --sandbox-state-json= | --sandbox-state-readable-root= | \
                          --permission-profile= | --permissions-profile= | -P= | \
                          --config= | -c= | --enable= | --disable=${codexSandboxDarwinEmptyCase})
                            codex_scan_index=$((codex_scan_index + 1))
                            continue
                            ;;
                          -C= | --cd=)
                            codex_recognized=0
                            break
                            ;;
                          --sandbox-state-json=?* | --sandbox-state-readable-root=?* | \
                          --permission-profile=?* | --permissions-profile=?* | -P?* | \
                          -C?* | --cd=?* | --config=?* | -c?* | \
                          --enable=?* | --disable=?* | --sandbox-state-disable-network | \
                          --include-managed-config${codexSandboxDarwinAttachedCase}${codexSandboxDarwinFlagCase})
                            codex_scan_index=$((codex_scan_index + 1))
                            continue
                            ;;
                          -) break ;;
                          -*)
                            codex_recognized=0
                            break
                            ;;
                          *) break ;;
                        esac
                      fi
                      codex_scan_index=$((codex_scan_index + 1))
                    done

                    if [ "$codex_generic_command" -eq 1 ] \
                      && [ "$codex_recognized" -eq 1 ]; then
                      case "$codex_command" in
                        exec | e)
                          [ "$codex_generic_positionals" -le 1 ] || codex_recognized=0
                          ;;
                        resume | fork)
                          [ "$codex_generic_positionals" -le 2 ] || codex_recognized=0
                          if [ "$codex_generic_last" -eq 1 ] \
                            && [ "$codex_generic_positionals" -gt 1 ]; then
                            codex_recognized=0
                          fi
                          ;;
                        archive | delete | unarchive)
                          [ "$codex_generic_positionals" -eq 1 ] || codex_recognized=0
                          ;;
                      esac
                      if [ "$codex_generic_approval_seen" -eq 1 ] \
                        && [ "$codex_generic_bypass_seen" -eq 1 ]; then
                        codex_recognized=0
                      fi
                      if [ "$codex_generic_full_auto_seen" -eq 1 ] \
                        && [ "$codex_generic_bypass_seen" -eq 1 ]; then
                        codex_recognized=0
                      fi
                    elif [ "$codex_command" = sandbox ] \
                      && [ "$codex_recognized" -eq 1 ]; then
                      if [ "$codex_sandbox_state_json" -gt 1 ] \
                        || [ "$codex_sandbox_disable_network" -gt 1 ] \
                        || [ "$codex_sandbox_permission_profile" -gt 1 ] \
                        || [ "$codex_sandbox_cwd" -gt 1 ] \
                        || [ "$codex_sandbox_include_managed" -gt 1 ] \
                        || [ "$codex_sandbox_log_denials" -gt 1 ]; then
                        codex_recognized=0
                      elif { [ "$codex_sandbox_readable_root" -eq 1 ] \
                        || [ "$codex_sandbox_disable_network" -eq 1 ]; } \
                        && [ "$codex_sandbox_state_json" -eq 0 ]; then
                        codex_recognized=0
                      elif { [ "$codex_sandbox_cwd" -eq 1 ] \
                        || [ "$codex_sandbox_include_managed" -eq 1 ]; } \
                        && [ "$codex_sandbox_permission_profile" -eq 0 ]; then
                        codex_recognized=0
                      elif [ "$codex_sandbox_state_json" -eq 1 ] \
                        && { [ "$codex_sandbox_permission_profile" -eq 1 ] \
                          || [ "$codex_sandbox_cwd" -eq 1 ] \
                          || [ "$codex_sandbox_include_managed" -eq 1 ]; }; then
                        codex_recognized=0
                      fi
                    fi
                  else
                    case "$codex_command" in
                      debug) codex_child_index=$((codex_debug_command_index + 1)) ;;
                      review)
                        codex_child_index=$((codex_command_index + 1))
                        codex_review_uncommitted=0
                        codex_review_base=0
                        codex_review_commit=0
                        codex_review_title=0
                        codex_review_strict=0
                        ;;
                    esac
                    codex_child_prompt_seen=0
                    while [ "$codex_child_index" -lt "''${#codex_arguments[@]}" ]; do
                      codex_argument="''${codex_arguments[$codex_child_index]}"
                      case "$codex_argument" in
                        --)
                          codex_child_remaining=$((''${#codex_arguments[@]} - codex_child_index - 1))
                          if [ $((codex_child_prompt_seen + codex_child_remaining)) -gt 1 ]; then
                            codex_recognized=0
                          fi
                          codex_child_prompt_seen=$((codex_child_prompt_seen + codex_child_remaining))
                          break
                          ;;
                        -c | --config | --enable | --disable)
                          if [ $((codex_child_index + 1)) -ge "''${#codex_arguments[@]}" ] \
                            || codex_value_looks_like_option \
                              "''${codex_arguments[$((codex_child_index + 1))]}"; then
                            codex_recognized=0
                            break
                          fi
                          codex_child_index=$((codex_child_index + 2))
                          continue
                          ;;
                        --config=* | -c?* | --enable=* | --disable=*)
                          codex_child_index=$((codex_child_index + 1))
                          continue
                          ;;
                      esac

                      if [ "$codex_command" = review ]; then
                        case "$codex_argument" in
                          --strict-config)
                            codex_review_strict=$((codex_review_strict + 1))
                            codex_child_index=$((codex_child_index + 1))
                            continue
                            ;;
                          --uncommitted)
                            codex_review_uncommitted=$((codex_review_uncommitted + 1))
                            codex_child_index=$((codex_child_index + 1))
                            continue
                            ;;
                          --base | --commit | --title)
                            if [ $((codex_child_index + 1)) -ge "''${#codex_arguments[@]}" ] \
                              || codex_value_looks_like_option \
                                "''${codex_arguments[$((codex_child_index + 1))]}"; then
                              codex_recognized=0
                              break
                            fi
                            case "$codex_argument" in
                              --base) codex_review_base=$((codex_review_base + 1)) ;;
                              --commit) codex_review_commit=$((codex_review_commit + 1)) ;;
                              --title) codex_review_title=$((codex_review_title + 1)) ;;
                            esac
                            codex_child_index=$((codex_child_index + 2))
                            continue
                            ;;
                          --base=* | --commit=* | --title=*)
                            case "$codex_argument" in
                              --base=*) codex_review_base=$((codex_review_base + 1)) ;;
                              --commit=*) codex_review_commit=$((codex_review_commit + 1)) ;;
                              --title=*) codex_review_title=$((codex_review_title + 1)) ;;
                            esac
                            codex_child_index=$((codex_child_index + 1))
                            continue
                            ;;
                        esac
                      else
                        case "$codex_argument" in
                          -i | --image)
                            codex_child_index=$((codex_child_index + 1))
                            if [ "$codex_child_index" -ge "''${#codex_arguments[@]}" ] \
                              || [ -z "''${codex_arguments[$codex_child_index]}" ] \
                              || codex_value_looks_like_option \
                                "''${codex_arguments[$codex_child_index]}"; then
                              codex_recognized=0
                              break
                            fi
                            while [ "$codex_child_index" -lt "''${#codex_arguments[@]}" ] \
                              && ! codex_value_looks_like_option \
                                "''${codex_arguments[$codex_child_index]}"; do
                              if ! codex_image_value_is_valid \
                                "''${codex_arguments[$codex_child_index]}"; then
                                codex_recognized=0
                                break
                              fi
                              codex_child_index=$((codex_child_index + 1))
                            done
                            [ "$codex_recognized" -eq 1 ] || break
                            continue
                            ;;
                          --image= | -i=)
                            codex_recognized=0
                            break
                            ;;
                          --image=?* | -i?*)
                            case "$codex_argument" in
                              --image=*) codex_image_value="''${codex_argument#--image=}" ;;
                              *)
                                codex_image_value="''${codex_argument#-i}"
                                codex_image_value="''${codex_image_value#=}"
                                ;;
                            esac
                            if ! codex_image_value_is_valid "$codex_image_value"; then
                              codex_recognized=0
                              break
                            fi
                            codex_child_index=$((codex_child_index + 1))
                            continue
                            ;;
                        esac
                      fi

                      case "$codex_argument" in
                        -)
                          if [ "$codex_child_prompt_seen" -eq 1 ]; then
                            codex_recognized=0
                            break
                          fi
                          codex_child_prompt_seen=1
                          codex_child_index=$((codex_child_index + 1))
                          ;;
                        -*)
                          codex_recognized=0
                          break
                          ;;
                        *)
                          if [ "$codex_child_prompt_seen" -eq 1 ]; then
                            codex_recognized=0
                            break
                          fi
                          codex_child_prompt_seen=1
                          codex_child_index=$((codex_child_index + 1))
                          ;;
                      esac
                    done

                    if [ "$codex_command" = review ] \
                      && [ "$codex_recognized" -eq 1 ]; then
                      codex_review_selectors=$((
                        codex_review_uncommitted
                        + codex_review_base
                        + codex_review_commit
                        + codex_child_prompt_seen
                      ))
                      if [ "$codex_review_selectors" -gt 1 ] \
                        || [ "$codex_review_uncommitted" -gt 1 ] \
                        || [ "$codex_review_base" -gt 1 ] \
                        || [ "$codex_review_commit" -gt 1 ] \
                        || [ "$codex_review_title" -gt 1 ] \
                        || [ "$codex_review_strict" -gt 1 ] \
                        || { [ "$codex_review_title" -eq 1 ] \
                          && [ "$codex_review_commit" -eq 0 ]; }; then
                        codex_recognized=0
                      fi
                    fi
                  fi

                  if [ "$codex_recognized" -eq 1 ] \
                    && { [ "$codex_root_remote_auth_seen" -eq 1 ] \
                      || [ "$codex_child_remote_auth_seen" -eq 1 ]; } \
                    && [ "$codex_root_remote_seen" -eq 0 ] \
                    && [ "$codex_child_remote_seen" -eq 0 ]; then
                    codex_recognized=0
                  fi

                  if [ "$codex_recognized" -eq 1 ] \
                    && [ "$codex_profile_conflict" -eq 1 ]; then
                    printf '%s\n' \
                      'codex: managed configuration conflicts with a caller profile' >&2
                    exit 2
                  fi
                  if [ "$codex_recognized" -eq 1 ]; then
                    codex_prepare_runtime_profile
                    exec -a codex @codex_unwrapped@ --profile nix-runtime "$@"
                  fi
                fi
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
    else if name == "droid" then
      let
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
    else if name == "pi" then
      assert (package.version or null) == "0.81.1";
      assert package ? overrideAttrs;
      package.overrideAttrs (old: {
        preInstall = ''
          cat > pi-tool-renderer-wrapper.sha256 <<'EOF'
          2cb700fcef4f36f853a22e2e90394d11e90fc3c0868d5c116cbf6cd00a680ae4  dist/core/agent-session.js
          5ebc2b2d8e13e0d90d6279d34e016b6f441208af9e73f3d4e75975376eb8987c  dist/core/extensions/loader.js
          5105a2d9097724972947860b81c5048109534fa909c07f7cc5495f3aaf30444b  dist/core/extensions/runner.js
          b7878c503c0d4ef7a9ad878775b67a7e99ee8e56005d55e973c8aad4ca116b10  dist/core/extensions/runner.d.ts
          ae5e0715c519006e744032ed50bb6552b9d4e3c17c600d046bf5c4d7160584ac  dist/core/extensions/types.d.ts
          EOF
          sha256sum -c pi-tool-renderer-wrapper.sha256
          patch -p1 --fuzz=0 < ${../overlays/ai/patches/pi-tool-renderer-wrapper.patch}
          ${pkgs.nodejs_22}/bin/node \
            ${../tests/ai/pi-tool-renderer-wrapper.test.mjs} "$PWD"
        ''
        + (old.preInstall or "");

        # Bun's compiled Linux executable names the dynamic loader as a
        # shared dependency. Invoking it normally mixes the Nix loader with
        # the host libc and segfaults; retain the matching loader wrapper.
        postInstall =
          (old.postInstall or "")
          + pkgs.lib.optionalString pkgs.stdenv.isLinux (
            let
              dynamicLinker = pkgs.stdenv.cc.bintools.dynamicLinker;
            in
            ''
              mv "$out/libexec/pi/pi" "$out/libexec/pi/pi.bin"
              makeWrapper ${pkgs.lib.escapeShellArg dynamicLinker} "$out/libexec/pi/pi" \
                --add-flags ${pkgs.lib.escapeShellArg "--library-path ${builtins.dirOf dynamicLinker}"} \
                --add-flags ${pkgs.lib.escapeShellArg "--argv0 pi"} \
                --add-flags "$out/libexec/pi/pi.bin"
            ''
          );

        passthru = (old.passthru or { }) // {
          toolRendererWrapperAbi = 1;
        };
      })
    else if
      name == "gemini-cli" && (package.version or null) == "0.49.0" && package ? overrideAttrs
    then
      package.overrideAttrs (
        old:
        let
          postPatch =
            builtins.replaceStrings [ "\nnode " ] [ "\n${pkgs.lib.getExe pkgs.nodejs} " ]
              old.postPatch;
        in
        {
          inherit postPatch;
          # llm-agents.nix 0.49.0 runs a Node script in postPatch. That
          # postPatch also runs inside fetchNpmDeps, whose default build
          # inputs do not include nodejs.
          npmDeps = pkgs.fetchNpmDeps {
            name = "${old.pname}-${old.version}-npm-deps-aligned";
            inherit (old) src;
            inherit postPatch;
            hash = old.npmDepsHash;
            fetcherVersion = old.npmDepsFetcherVersion;
            nativeBuildInputs = [ pkgs.nodejs ];
          };
        }
      )
    else
      package;

  optAgent =
    pkgs: name:
    let
      system = pkgs.stdenv.hostPlatform.system;
      agentPackages = llm-agents.packages.${system} or { };
    in
    if agentPackages ? ${name} then [ (patchAgentPackage pkgs name agentPackages.${name}) ] else [ ];

  pythonAiEnv =
    pkgs:
    pkgs.python3.withPackages (
      ps:
      with ps;
      [
        hf-xet
        huggingface-hub
        llm
        openai
        python-dotenv
        requests
        tiktoken
      ]
      ++ pkgs.lib.optionals (pkgs.stdenv.isDarwin && pkgs.stdenv.isAarch64 && ps ? llm-mlx) [
        llm-mlx
      ]
      ++ pkgs.lib.optionals (pkgs.stdenv.isDarwin && pkgs.stdenv.isAarch64 && ps ? mlx-speech) [
        mlx-speech
      ]
    );

  aiPackagesFor =
    pkgs:
    let
      system = pkgs.stdenv.hostPlatform.system;
      inherit (pkgs) lib;
      opt = optPkg pkgs;
      agent = optAgent pkgs;
      appleSilicon = pkgs.stdenv.isDarwin && pkgs.stdenv.isAarch64;
      gitAiPackages = git-ai.packages.${system} or { };
    in
    [
      (lib.hiPrio (pythonAiEnv pkgs))
      (lib.hiPrio pkgs.llama-cpp)
      pkgs.nodejs_22
      pkgs.openmpi
      pkgs.qdrant
      pkgs.uv
    ]
    ++ lib.optionals (gitAiPackages ? minimal) [ gitAiPackages.minimal ]
    ++ agent "claude-code"
    ++ agent "ccusage"
    ++ agent "codex"
    ++ agent "droid"
    ++ agent "gemini-cli"
    ++ agent "git-surgeon"
    ++ agent "mcporter"
    ++ agent "opencode"
    ++ agent "pi"
    ++ opt "aiperf"
    ++ opt "agent-deck"
    ++ opt "plasma-wiki"
    ++ opt "plasma-fractal"
    ++ opt "agnix"
    ++ opt "claude-replay"
    ++ opt "claude-vault"
    ++ opt "context-hub"
    ++ opt "context7-mcp"
    ++ opt "gguf-tools"
    ++ opt "github-mcp-server"
    ++ opt "guidellm"
    ++ opt "hfdownloader"
    ++ opt "lazycodex-ai"
    ++ opt "llama-swap"
    ++ opt "openai-whisper"
    ++ opt "pal-mcp-server"
    ++ opt "playwright-mcp"
    ++ opt "qdrant-web-ui"
    ++ opt "rustdocs-mcp-server"
    ++ opt "sherlock-db"
    ++ lib.optionals (pkgs ? mcp-server-sequential-thinking) [
      (lib.hiPrio pkgs.mcp-server-sequential-thinking)
    ]
    ++ lib.optionals pkgs.stdenv.isDarwin (opt "drafts-mcp-server")
    ++ lib.optionals appleSilicon (opt "mlx-lm" ++ opt "mtplx" ++ opt "omlx" ++ opt "vllm-mlx");

  mkAiToolchain =
    pkgs:
    pkgs.buildEnv {
      name = "ai-nix-toolchain";
      paths = aiPackagesFor pkgs;
      ignoreCollisions = true;
    };

  devToolPackages =
    pkgs: with pkgs; [
      deadnix
      findutils
      gawk
      git
      gnugrep
      gnused
      hyperfine
      jq
      lefthook
      nix
      nixfmt
      shellcheck
      shfmt
      statix
    ];

  qualityInputs = pkgs: rec {
    common = with pkgs; [
      bash
      coreutils
      findutils
      gawk
      git
      gnugrep
      gnused
      jq
    ];

    format =
      common
      ++ (with pkgs; [
        nixfmt
        shfmt
      ]);
    lint =
      common
      ++ (with pkgs; [
        deadnix
        shellcheck
        statix
      ]);
    test = common ++ (with pkgs; [ nix ]);
    build = common ++ (with pkgs; [ nix ]);
    all =
      common
      ++ (with pkgs; [
        deadnix
        nix
        nixfmt
        shellcheck
        shfmt
        statix
      ]);
  };

  sourceForChecks = lib.cleanSourceWith {
    src = ../.;
    filter =
      path: _type:
      let
        name = builtins.baseNameOf path;
      in
      !(
        name == ".git"
        || name == ".direnv"
        || name == "build"
        || name == "result"
        || lib.hasPrefix "result-" name
      );
  };

  scriptRoot = ../tests/ai/scripts;

  mkScriptPackage =
    pkgs: name: scriptName: runtimeInputs:
    pkgs.writeShellApplication {
      name = "ai-nix-${name}";
      inherit runtimeInputs;
      text = ''
        exec ${pkgs.bash}/bin/bash ${scriptRoot}/${scriptName} "$@"
      '';
    };

  mkScriptApp =
    pkgs: name: scriptName: runtimeInputs:
    let
      package = mkScriptPackage pkgs name scriptName runtimeInputs;
    in
    {
      type = "app";
      program = "${package}/bin/ai-nix-${name}";
      meta.description = "Run the ai-nix ${name} target";
    };

  mkScriptCheck =
    pkgs: name: scriptName: runtimeInputs: extraEnv:
    pkgs.runCommand "ai-nix-${name}"
      {
        nativeBuildInputs = runtimeInputs;
      }
      ''
        export HOME=$TMPDIR
        export AI_NIX_ROOT=${sourceForChecks}
        export AI_NIX_OUTPUT_ROOT=$TMPDIR/build
        ${extraEnv}

        ${pkgs.bash}/bin/bash ${scriptRoot}/${scriptName}

        mkdir -p "$out"
        if [ -d "$AI_NIX_OUTPUT_ROOT" ]; then
          cp -R "$AI_NIX_OUTPUT_ROOT"/. "$out"/
        fi
        touch "$out/${name}.ok"
      '';
in
{
  overlays.default = lib.composeManyExtensions overlays;

  lib = {
    inherit aiPackagesFor patchAgentPackage;
  };

  devShells = forAllSystems (
    system:
    let
      pkgs = mkPkgs system;
    in
    {
      default = pkgs.mkShell {
        packages = aiPackagesFor pkgs ++ devToolPackages pkgs;

        shellHook = ''
          export DISABLE_AUTOUPDATER="1"
          export ET_NO_TELEMETRY="1"
          export FACTORY_AUTO_UPDATE="false"
          export HF_HUB_ENABLE_HF_TRANSFER="1"
          export SSL_CERT_FILE="${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt"
          export REQUESTS_CA_BUNDLE="''${REQUESTS_CA_BUNDLE:-$SSL_CERT_FILE}"
        '';
      };
    }
  );

  packages = forAllSystems (
    system:
    let
      pkgs = mkPkgs system;
    in
    {
      default = mkAiToolchain pkgs;
      inherit (pkgs)
        agent-browser
        agent-http-header-bridge
        agent-resources
        bigpowers
        lean-ctx
        pi-agent-browser-native
        pi-artifacts
        pi-btw
        pi-dynamic-workflows
        pi-gallery
        pi-insights
        pi-hashline-edit-pro
        pi-lean-ctx
        pi-lens
        pi-ponytail
        pi-subagentura
        pi-web-access
        plasma-fractal
        plasma-wiki
        ;
    }
  );

  apps = forAllSystems (
    system:
    let
      pkgs = mkPkgs system;
      inputs = qualityInputs pkgs;
      app =
        name: scriptName: runtimeInputs:
        mkScriptApp pkgs name scriptName runtimeInputs;
    in
    rec {
      format = app "format" "format.sh" inputs.format;
      format-check = app "format-check" "format-check.sh" inputs.format;
      lint = app "lint" "lint.sh" inputs.lint;
      test = app "test" "test.sh" inputs.test;
      build-check = app "build-check" "build-check.sh" inputs.build;
      no-warnings = app "no-warnings" "no-warnings.sh" inputs.build;
      coverage = test;
      coverage-check = test;
      profile = build-check;
      profile-check = build-check;
      fuzz = test;
      memory-check = test;
      check = app "check" "check.sh" inputs.all;
      default = check;
    }
  );

  checks = forAllSystems (
    system:
    let
      pkgs = mkPkgs system;
      inputs = qualityInputs pkgs;
      check =
        name: scriptName: runtimeInputs: extraEnv:
        mkScriptCheck pkgs name scriptName runtimeInputs extraEnv;
    in
    rec {
      build = mkAiToolchain pkgs;
      agent-deck-go-compat = pkgs.callPackage ../overlays/tests/agent-deck-go-compat.nix { };
      fractal-smoke = pkgs.callPackage ../overlays/tests/plasma-fractal-smoke.nix { };
      llama-cpp-platform-compat = pkgs.callPackage ../overlays/tests/llama-cpp-platform-compat.nix { };
      llm-agents-nixpkgs-independent =
        let
          lock = builtins.fromJSON (builtins.readFile ../config/ai/flake.lock);
          llmAgentsNode = lock.nodes.${lock.nodes.root.inputs.llm-agents};
        in
        if builtins.isString llmAgentsNode.inputs.nixpkgs then
          pkgs.runCommand "llm-agents-nixpkgs-independent" { } "touch $out"
        else
          throw "ai-nix llm-agents must retain its own nixpkgs input";
      agent-resources = pkgs.callPackage ../tests/ai/agent-resources.nix {
        inherit (pkgs.inputs)
          bigpowers
          ponytail
          translate-tool
          ;
        gitSurgeonSource = pkgs.inputs.llm-agents.packages.${system}.git-surgeon.src;
        sourceOnlyResources = pkgs.callPackage ./agent-resources.nix {
          inputs = pkgs.inputs // {
            llm-agents = builtins.removeAttrs pkgs.inputs.llm-agents [ "packages" ];
          };
        };
        piMcpAdapter = pkgs.inputs.pi-mcp-adapter;
        piOpenaiServerCompaction = pkgs.inputs.pi-openai-server-compaction;
        piQuiet = pkgs.inputs.pi-quiet;
        piPackage = patchAgentPackage pkgs "pi" pkgs.inputs.llm-agents.packages.${system}.pi;
      };
      agent-wrappers = pkgs.callPackage ../tests/ai/agent-wrappers.nix {
        inherit patchAgentPackage;
        claudePackage = pkgs.inputs.llm-agents.packages.${system}.claude-code;
        codexPackage = pkgs.inputs.llm-agents.packages.${system}.codex;
        agentHttpHeaderBridge = pkgs.agent-http-header-bridge or null;
        agentHttpHeaderBridgeOutput = pkgs.agent-http-header-bridge or null;
        mcpRemote = pkgs.inputs.mcp-remote or null;
      };
      pi-gallery = pkgs.callPackage ../tests/ai/pi-gallery.nix {
        piPackage = patchAgentPackage pkgs "pi" pkgs.inputs.llm-agents.packages.${system}.pi;
        piPackages = {
          inherit (pkgs)
            agent-browser
            agent-resources
            bigpowers
            lean-ctx
            pi-agent-browser-native
            pi-artifacts
            pi-btw
            pi-dynamic-workflows
            pi-gallery
            pi-insights
            pi-hashline-edit-pro
            pi-lean-ctx
            pi-lens
            pi-ponytail
            pi-subagentura
            pi-web-access
            ;
        };
      };
      format = check "format" "format-check.sh" inputs.format "";
      lint = check "lint" "lint.sh" inputs.lint "";
      tests = check "tests" "test.sh" inputs.test ''
        export AI_NIX_TEST_SOURCE_ONLY=1
      '';
      coverage = tests;
      profile = build;
      fuzz = tests;
      memory = tests;
      no-warnings = check "no-warnings" "lint.sh" inputs.lint "";
    }
  );

  formatter = forAllSystems (
    system:
    let
      pkgs = mkPkgs system;
    in
    mkScriptPackage pkgs "format" "format.sh" (qualityInputs pkgs).format
  );
}
