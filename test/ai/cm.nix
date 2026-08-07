{
  jq,
  lib,
  pkgs,
  runCommand,
}:

let
  upstreamVersion = "0.2.13";
in
runCommand "cm-integration-check"
  {
    nativeBuildInputs = [
      jq
      pkgs.coreutils
      pkgs.findutils
      pkgs.gnugrep
    ]
    ++ lib.optional pkgs.stdenv.hostPlatform.isDarwin pkgs.darwin.cctools;
  }
  ''
    set -euo pipefail
    umask 077

    cm=${pkgs.cm}/bin/cm
    cass=${pkgs.cass}/bin/cass

    test "$($cm --version)" = "${upstreamVersion}"
    test "$(sha256sum ${pkgs.cm}/share/licenses/cm/LICENSE | cut -d ' ' -f1)" =       32a82e0a5754e72e51fae44b65a936c831c07376f21c90f5fb9e76897fcc3509
    grep -F '${pkgs.cass}/bin' "$cm" >/dev/null
    grep -F '${pkgs.git}/bin' "$cm" >/dev/null
    grep -F '${pkgs.openssh}/bin' "$cm" >/dev/null
    grep -F '${pkgs.python3}/bin' "$cm" >/dev/null
    ${lib.optionalString pkgs.stdenv.hostPlatform.isDarwin ''
      ${pkgs.darwin.cctools}/bin/otool -l ${pkgs.cm}/libexec/cm/cm \
        | grep -F 'LC_CODE_SIGNATURE' >/dev/null
    ''}

    $cm --help >help.out 2>help.err
    grep -F 'Usage: cm' help.out >/dev/null
    grep -F 'Procedural memory for AI coding agents' help.out >/dev/null
    test ! -s help.err

    sandbox=$TMPDIR/cm-contract
    home=$sandbox/home
    xdg_config=$sandbox/xdg-config
    xdg_data=$sandbox/xdg-data
    xdg_cache=$sandbox/xdg-cache
    state=$sandbox/state
    cass_state=$sandbox/cass-state
    project=$sandbox/project
    results=$sandbox/results
    mkdir -m 700 -p       "$home" "$xdg_config" "$xdg_data" "$xdg_cache"       "$state" "$project" "$results"

    export HOME="$home"
    export XDG_CONFIG_HOME="$xdg_config"
    export XDG_DATA_HOME="$xdg_data"
    export XDG_CACHE_HOME="$xdg_cache"
    export CASS_MEMORY_HOME="$state"
    export CASS_DATA_DIR="$cass_state"
    export CASS_IGNORE_SOURCES_CONFIG=1
    unset       OPENAI_API_KEY       ANTHROPIC_API_KEY       GOOGLE_GENERATIVE_AI_API_KEY       AWS_ACCESS_KEY_ID       AWS_SECRET_ACCESS_KEY       AWS_SESSION_TOKEN       AWS_SHARED_CREDENTIALS_FILE       AWS_CONFIG_FILE       CASS_PATH       CASS_MEMORY_CLI_NAME

    # A compiled Bun executable must not auto-load cwd dotenv state.
    printf '%s\n' 'CASS_MEMORY_CLI_NAME=dotenv-injected-name' >"$project/.env"
    (
      cd "$project"
      $cm quickstart --json >"$results/quickstart.json" 2>"$results/quickstart.err"
    )
    jq -e       '.success == true
       and .command == "quickstart"
       and .data.oneCommand == "cm context \"<task>\" --json"
       and .metadata.version == "${upstreamVersion}"'       "$results/quickstart.json" >/dev/null
    test ! -s "$results/quickstart.err"
    test -z "$(find "$home" "$xdg_config" "$xdg_data" "$xdg_cache" "$state" -mindepth 1 -print -quit)"

    $cm init --json --no-interactive >"$results/init.json" 2>"$results/init.err"
    jq -e       --arg state "$state"       '.success == true
       and .command == "init"
       and .data.configPath == ($state + "/config.json")
       and (.data.created | sort) == ["blocked.log", "config.json", "playbook.yaml", "usage.jsonl"]
       and .data.existed == []
       and .data.cassAvailable == true'       "$results/init.json" >/dev/null
    test ! -s "$results/init.err"
    jq -e 'has("apiKey") | not' "$state/config.json" >/dev/null

    cat >"$results/expected-state" <<'EOF'
    blocked.log
    config.json
    cost
    diary
    embeddings
    playbook.yaml
    reflections
    usage.jsonl
    EOF
    (cd "$state" && find . -mindepth 1 -maxdepth 1 -print | sed 's#^./##' | sort) >"$results/actual-state"
    diff -u "$results/expected-state" "$results/actual-state"
    test -z "$(find "$state" -type d ! -perm 700 -print -quit)"
    test -z "$(find "$state" -type f ! -perm 600 -print -quit)"

    fixture=$project/.aider.chat.history.md
    cat >"$fixture" <<'EOF'

    > cmnixfixturetoken

    assistant says cmnixfixturetoken response
    EOF
    cp "$fixture" "$results/fixture.before"
    export CASS_AIDER_DATA_ROOT="$fixture"

    (
      cd "$project"
      $cass --color=never index         --watch-once "$fixture"         --json         --no-progress-events         --data-dir "$cass_state"         >"$results/index.json" 2>"$results/index.err"
    )
    jq -e '.success == true and .conversations == 1 and .messages == 2'       "$results/index.json" >/dev/null
    test ! -s "$results/index.err"
    test ! -e "$cass_state/watch_state.json"
    cmp "$results/fixture.before" "$fixture"

    (
      cd "$project"
      $cm context cmnixfixturetoken --history 5 --days 30 --json         >"$results/context.json" 2>"$results/context.err"
    )
    jq -e       '.success == true
       and .command == "context"
       and .data.task == "cmnixfixturetoken"
       and (.data.historySnippets | length) >= 1
       and any(.data.historySnippets[]; .snippet | contains("cmnixfixturetoken"))'       "$results/context.json" >/dev/null
    test ! -s "$results/context.err"
    cmp "$results/fixture.before" "$fixture"

    # Global and CLI apiKey fields are rejected before their values can be used.
    guard_state=$sandbox/guard-state
    mkdir -m 700 "$guard_state"
    printf '%s\n' '{"apiKey":""}' >"$guard_state/config.json"
    chmod 600 "$guard_state/config.json"
    if CASS_MEMORY_HOME="$guard_state" $cm context rejected --json       >"$results/guard.out" 2>"$results/guard.err"
    then
      echo "cm accepted a file-backed apiKey field" >&2
      exit 1
    fi
    cat "$results/guard.out" "$results/guard.err" >"$results/guard.combined"
    grep -F 'apiKey configuration field is disabled' "$results/guard.combined" >/dev/null

    # Repository-local credentials are rejected, not silently filtered, and their
    # values must never appear in diagnostics, paths, links, or persisted files.
    ${pkgs.git}/bin/git -C "$project" init --quiet
    mkdir -m 700 "$sandbox/.cass" "$project/.cass" "$project/nested"
    repo_guard_sentinel=repo-credential-value-must-not-appear
    printf '%s\n' '{"apiKey":"repo-credential-value-must-not-appear"}' \
      >"$project/.cass/config.json"
    cp "$project/.cass/config.json" "$sandbox/.cass/config.json"
    chmod 600 "$sandbox/.cass/config.json" "$project/.cass/config.json"
    if (
      cd "$project/nested"
      $cm context rejected --json
    ) >"$results/repo-guard.out" 2>"$results/repo-guard.err"
    then
      echo "cm accepted a repository-local apiKey field" >&2
      exit 1
    fi
    test ! -s "$results/repo-guard.err"
    jq -s -e \
      'length == 1
       and (.[0]
         | .success == false
         and .command == "context"
         and (.error.message | contains("apiKey configuration field is disabled")))' \
      "$results/repo-guard.out" >/dev/null
    test "$(jq -r .apiKey "$project/.cass/config.json")" = "$repo_guard_sentinel"
    rm "$project/.cass/config.json"
    rmdir "$project/.cass"

    # Discovery stops at the Git root rather than walking into an outer decoy.
    (
      cd "$project/nested"
      $cm context cmnixfixturetoken --history 5 --days 30 --json
    ) >"$results/repo-boundary.out" 2>"$results/repo-boundary.err"
    test ! -s "$results/repo-boundary.err"
    jq -s -e \
      'length == 1
       and (.[0] | .success == true and .command == "context")' \
      "$results/repo-boundary.out" >/dev/null
    test "$(jq -r .apiKey "$sandbox/.cass/config.json")" = "$repo_guard_sentinel"
    rm "$sandbox/.cass/config.json"
    rmdir "$sandbox/.cass"

    scan_paths=$results/repo-guard-scan-paths
    : >"$scan_paths"
    find "$sandbox" -print0 >"$scan_paths"
    while IFS= read -r -d $'\0' scan_path; do
      case "$scan_path" in
        *"$repo_guard_sentinel"*)
          echo "cm persisted a repository-local apiKey value in a path" >&2
          exit 1
          ;;
      esac
      if test -L "$scan_path"; then
        scan_target=$(readlink "$scan_path")
        case "$scan_target" in
          *"$repo_guard_sentinel"*)
            echo "cm persisted a repository-local apiKey value in a link" >&2
            exit 1
            ;;
        esac
      elif test -f "$scan_path"; then
        if grep -F -q -- "$repo_guard_sentinel" "$scan_path"; then
          echo "cm emitted or persisted a repository-local apiKey value" >&2
          exit 1
        else
          scan_status=$?
          if test "$scan_status" -ne 1; then
            echo "failed to scan CM state for a repository-local apiKey value" >&2
            exit 1
          fi
        fi
      fi
    done <"$scan_paths"

    for dir in "$home" "$xdg_config" "$xdg_data" "$xdg_cache"; do
      test -z "$(find "$dir" -mindepth 1 -print -quit)"
    done

    mkdir -p "$out"
    cp "$results/quickstart.json" "$out/quickstart.json"
    cp "$results/context.json" "$out/context.json"
    touch "$out/passed"
  ''
