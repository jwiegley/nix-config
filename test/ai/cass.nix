{
  jq,
  pkgs,
  runCommand,
}:

let
  source = (import ../../packages/source-catalog.nix "ai").cass;
in
runCommand "cass-integration-check"
  {
    nativeBuildInputs = [ jq ];
  }
  ''
        set -euo pipefail

        cass=${pkgs.cass}/bin/cass
        test "$($cass --version)" = "cass ${source.version}"
        cmp ${../../packages/cass/LICENSE} ${pkgs.cass}/share/licenses/cass/LICENSE
        grep -F 'CODING_AGENT_SEARCH_NO_UPDATE_PROMPT' "$cass" >/dev/null
        grep -F '${pkgs.openssh}/bin' "$cass" >/dev/null
        grep -F '${pkgs.rsync}/bin' "$cass" >/dev/null
        ! grep -F 'TUI_HEADLESS' "$cass" >/dev/null

        $cass --help >help.out 2>help.err
        grep -F 'Usage:' help.out >/dev/null
        grep -F 'Launch interactive TUI' help.out >/dev/null
        test ! -s help.err

        sandbox=$TMPDIR/cass-contract
        home=$sandbox/home
        xdg_config=$sandbox/xdg-config
        xdg_data=$sandbox/xdg-data
        xdg_cache=$sandbox/xdg-cache
        codex_home=$sandbox/codex
        gemini_home=$sandbox/gemini
        pi_home=$sandbox/pi
        opencode_home=$sandbox/opencode
        project=$sandbox/project
        state=$sandbox/state
        results=$sandbox/results
        mkdir -m 700 -p \
          "$home" "$xdg_config" "$xdg_data" "$xdg_cache" \
          "$codex_home" "$gemini_home" "$pi_home" "$opencode_home" \
          "$project" "$results"

        export HOME="$home"
        export XDG_CONFIG_HOME="$xdg_config"
        export XDG_DATA_HOME="$xdg_data"
        export XDG_CACHE_HOME="$xdg_cache"
        export CODEX_HOME="$codex_home"
        export GEMINI_HOME="$gemini_home"
        export PI_CODING_AGENT_DIR="$pi_home"
        export OPENCODE_STORAGE_ROOT="$opencode_home"
        export CASS_IGNORE_SOURCES_CONFIG=1

        $cass capabilities --json >"$results/capabilities.json" 2>"$results/capabilities.err"
        $cass api-version --json >"$results/api-version.json" 2>"$results/api-version.err"

        jq -e \
          --arg version "${source.version}" \
          '.version == $version
           and .api_version == 1
           and (.commands | length) > 10
           and any(.commands[]; .name == "tui" and .description == "Launch interactive TUI")' \
          "$results/capabilities.json" >/dev/null
        jq -e \
          --arg version "${source.version}" \
          '.crate_version == $version and .api_version == 1 and .contract_version == "1"' \
          "$results/api-version.json" >/dev/null
        test ! -s "$results/capabilities.err"
        test ! -s "$results/api-version.err"

        triage_state=$sandbox/triage-state
        $cass triage --data-dir "$triage_state" --json \
          >"$results/triage.json" 2>"$results/triage.err"
        jq -e \
          '.surface == "triage"
           and .schema_version == 1
           and .status == "not_initialized"
           and .initialized == false
           and (.recommended_commands | length) > 0' \
          "$results/triage.json" >/dev/null
        test ! -s "$results/triage.err"
        test ! -e "$triage_state"

        fixture=$project/.aider.chat.history.md
        cat >"$fixture" <<'EOF'

    > cassnixfixturetoken

    assistant says cassnixfixturetoken response
    EOF
        cp "$fixture" "$results/fixture.before"
        export CASS_AIDER_DATA_ROOT="$fixture"

        (
          cd "$project"
          $cass --color=never index \
            --watch-once "$fixture" \
            --json \
            --no-progress-events \
            --data-dir "$state" \
            >"$results/index.json" 2>"$results/index.err"
        )
        jq -e \
          --arg state "$state" \
          --arg db "$state/agent_search.db" \
          '.success == true
           and .entrypoint.kind == "watch_once"
           and .entrypoint.watch_once_path_count == 1
           and .data_dir == $state
           and .db_path == $db
           and .conversations == 1
           and .messages == 2
           and (.indexing_stats.connectors | any(.name == "aider"))' \
          "$results/index.json" >/dev/null
        test ! -s "$results/index.err"
        test -f "$state/agent_search.db"
        test -d "$state/index"
        test -d "$state/raw-mirror"
        test ! -e "$state/watch_state.json"
        cmp "$results/fixture.before" "$fixture"

        (
          cd "$project"
          $cass --color=never search cassnixfixturetoken \
            --json \
            --mode lexical \
            --fields minimal \
            --limit 5 \
            --data-dir "$state" \
            >"$results/search.json" 2>"$results/search.err"
        )
        jq -e \
          --arg fixture "$fixture" \
          '.total_matches >= 1
           and (.hits | length) >= 1
           and all(.hits[]; .source_path == $fixture and .agent == "aider")' \
          "$results/search.json" >/dev/null
        test ! -s "$results/search.err"
        cmp "$results/fixture.before" "$fixture"

        for dir in \
          "$home" "$xdg_config" "$xdg_data" "$xdg_cache" \
          "$codex_home" "$gemini_home" "$pi_home" "$opencode_home"
        do
          test -z "$(find "$dir" -mindepth 1 -print -quit)"
        done

        mkdir -p "$out"
        cp "$results/api-version.json" "$out/api-version.json"
        touch "$out/passed"
  ''
