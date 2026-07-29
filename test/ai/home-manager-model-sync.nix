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

  # The model-sync factory and its generated script. Pure evaluation: the
  # host-closure assertions that used to live in task10Checks now belong to
  # the integration check.
  checks = common.task10FactoryChecks;
in
assert builtins.deepSeq checks true;

pkgs.runCommand "ai-home-manager-model-sync"
  {
    nativeBuildInputs = [
      pkgs.findutils
      pkgs.jq
    ];
  }
  ''
    task10_root="$TMPDIR/task10-model-sync"
    task10_sentinel='TASK10-CREDENTIAL-SENTINEL-DO-NOT-LEAK'
    mkdir -p "$task10_root"

    task10_new_case() {
      label=$1
      task10_case="$task10_root/$label"
      rm -rf "$task10_case"
      mkdir -p "$task10_case/fake/prefs" "$task10_case/xdg-state"
      export TASK10_FAKE_STATE="$task10_case/fake"
      export TASK10_LOG="$task10_case/invocations.log"
      export XDG_STATE_HOME="$task10_case/xdg-state"
      export TASK10_EXPECTED_MODEL='${common.modelData.syncInputs.model}'
      export TASK10_EXPECTED_URL='${common.modelData.syncInputs.chatUrl}'
      unset TASK10_FAIL_AT
      : > "$TASK10_LOG"
      : > "$task10_case/stdout"
      : > "$task10_case/stderr"
      printf '%s' "$task10_sentinel" > "$TASK10_FAKE_STATE/devonthink-credential"
      : > "$TASK10_FAKE_STATE/iterm-key-metadata"
      task10_stamp="$XDG_STATE_HOME/nix-managed-ai/model-sync-v1.sha256"
    }

    task10_assert_redacted() {
      for output in "$TASK10_LOG" "$task10_case/stdout" "$task10_case/stderr"; do
        ! grep -Fq "$task10_sentinel" "$output"
      done
      test '${common.task10Digest}' != "$task10_sentinel"
      test '${common.task10ChangedDigest}' != "$task10_sentinel"
      if [ -e "$task10_stamp" ] && [ ! -d "$task10_stamp" ]; then
        ! grep -Fq "$task10_sentinel" "$task10_stamp"
      fi
      ! find "$TASK10_FAKE_STATE/prefs" -type f -exec grep -Fq "$task10_sentinel" {} \; \
        -print | grep -q .
    }

    task10_run_ok() {
      "$1" > "$task10_case/stdout" 2> "$task10_case/stderr"
      task10_assert_redacted
    }

    task10_run_fail() {
      if "$1" > "$task10_case/stdout" 2> "$task10_case/stderr"; then
        echo "Task 10 expected failure: $task10_case" >&2
        exit 1
      fi
      task10_assert_redacted
    }

    task10_assert_exact_app_calls() {
      ${pkgs.python3}/bin/python3 - \
        "$TASK10_LOG" "$TASK10_EXPECTED_MODEL" "$TASK10_EXPECTED_URL" <<'PY'
    import os
    import sys

    log_path, model, url = sys.argv[1:]
    with open(log_path, encoding="utf-8") as stream:
        calls = [tuple(line.rstrip("\n").split("\t")) for line in stream]

    defaults = sorted(call[1:] for call in calls if call[0] == "defaults")
    devon = "com.devon-technologies.think"
    iterm = "com.googlecode.iterm2"
    writes = [
        ("write", devon, "ChatEngine", "-int", "2"),
        ("write", devon, "ChatModel-OpenAI (Compatible)", "-string", model),
        ("write", devon, "OpenAI (Compatible)URL", "-string", url),
        ("write", devon, "ChatSummaryEngine", "-int", "2"),
        ("write", devon, "ChatSummaryModel", "-string", model),
        ("write", iterm, "UseRecommendedAIModel", "-bool", "false"),
        ("write", iterm, "AiModel", "-string", model),
        ("write", iterm, "AITermAPI", "-int", "1"),
        ("write", iterm, "AitermURL", "-string", url),
        ("write", iterm, "AIVendor", "-int", "2"),
    ]
    expected_defaults = sorted(
        writes + [("read", domain, key) for _, domain, key, _, _ in writes]
    )
    if defaults != expected_defaults:
        raise SystemExit(
            f"defaults allowlist mismatch:\nactual={defaults!r}\n"
            f"expected={expected_defaults!r}"
        )

    expected_security = (
        "find-generic-password",
        "-s",
        "iTerm2 API Keys",
        "-a",
        "OpenAI API Key for iTerm2",
    )
    security = [call[1:] for call in calls if call[0] == "security"]
    if security != [expected_security, expected_security]:
        raise SystemExit(f"security metadata calls mismatch: {security!r}")

    probes = [call[1:] for call in calls if call[0] == "devonthinkKeyPresent"]
    if probes != [(), ()]:
        raise SystemExit(f"DEVONthink Boolean probes mismatch: {probes!r}")

    pgrep = [call[1:] for call in calls if call[0] == "pgrep"]
    expected_pgrep = [
        ("-x", "DEVONthink"),
        ("-x", "DEVONthink 3"),
        ("-x", "iTerm2"),
    ]
    if pgrep != expected_pgrep:
        raise SystemExit(f"process guard calls mismatch: {pgrep!r}")

    state_dir = os.path.join(os.environ["XDG_STATE_HOME"], "nix-managed-ai")
    stamp = os.path.join(state_dir, "model-sync-v1.sha256")
    expected_exact = {
        "mkdir": [("-p", "--", state_dir)],
        "mktemp": [(stamp + ".tmp.XXXXXX",)],
        "rm": [],
    }
    for tool, expected in expected_exact.items():
        actual = [call[1:] for call in calls if call[0] == tool]
        if actual != expected:
            raise SystemExit(f"{tool} calls mismatch: {actual!r}")

    moves = [call[1:] for call in calls if call[0] == "mv"]
    if len(moves) != 1:
        raise SystemExit(f"mv call count mismatch: {moves!r}")
    move = moves[0]
    if (
        len(move) != 4
        or move[:2] != ("-fT", "--")
        or not move[2].startswith(stamp + ".tmp.")
        or move[3] != stamp
    ):
        raise SystemExit(f"atomic mv shape mismatch: {move!r}")

    expected_tools = {
        "defaults",
        "devonthinkKeyPresent",
        "mkdir",
        "mktemp",
        "mv",
        "pgrep",
        "security",
    }
    actual_tools = {call[0] for call in calls}
    if actual_tools != expected_tools:
        raise SystemExit(f"successful tool inventory mismatch: {actual_tools!r}")
    PY
    }

    # First run writes only the ten approved fields, verifies them, and stamps.
    task10_new_case first
    task10_run_ok '${common.task10Script}'
    test "$(cat "$task10_stamp")" = '${common.task10Digest}'
    task10_assert_exact_app_calls
    test -z "$(find "$(dirname "$task10_stamp")" -name 'model-sync-v1.sha256.tmp.*' -print)"

    # The digest fast path invokes no parameterized tool at all.
    : > "$TASK10_LOG"
    task10_run_ok '${common.task10Script}'
    test ! -s "$TASK10_LOG"
    test "$(cat "$task10_stamp")" = '${common.task10Digest}'

    # A corrupt multi-line stamp is never accepted as an unchanged digest.
    printf '%s\n' corrupt-trailing-line >> "$task10_stamp"
    : > "$TASK10_LOG"
    task10_run_ok '${common.task10Script}'
    test "$(cat "$task10_stamp")" = '${common.task10Digest}'
    task10_assert_exact_app_calls

    # A changed nonsecret selection updates once and replaces the digest.
    : > "$TASK10_LOG"
    export TASK10_EXPECTED_MODEL='${common.alternateModelData.syncInputs.model}'
    export TASK10_EXPECTED_URL='${common.alternateModelData.syncInputs.chatUrl}'
    task10_run_ok '${common.task10ChangedScript}'
    test "$(cat "$task10_stamp")" = '${common.task10ChangedDigest}'
    task10_assert_exact_app_calls

    # Every guarded process independently defers before credentials or writes.
    task10_process_index=0
    for process_name in DEVONthink 'DEVONthink 3' iTerm2; do
      task10_process_index=$((task10_process_index + 1))
      task10_new_case "running-$task10_process_index"
      printf '%s' "$process_name" > "$TASK10_FAKE_STATE/running"
      task10_run_ok '${common.task10Script}'
      test ! -e "$task10_stamp"
      grep -Fq \
        'nix-managed model sync: deferred while DEVONthink or iTerm2 is running' \
        "$task10_case/stderr"
      ! grep -Eq $'^(defaults|devonthinkKeyPresent|security)\t' "$TASK10_LOG"
      grep -Fq "pgrep	-x	$process_name" "$TASK10_LOG"
    done

    # An indeterminate process check fails closed.
    task10_new_case pgrep-error
    export TASK10_FAIL_AT=pgrep-error
    task10_run_fail '${common.task10Script}'
    test ! -e "$task10_stamp"
    ! grep -Eq $'^(defaults|devonthinkKeyPresent|security)\t' "$TASK10_LOG"

    # Missing credential-presence metadata blocks before any preference write.
    task10_new_case missing-devonthink-key
    rm "$TASK10_FAKE_STATE/devonthink-credential"
    task10_run_fail '${common.task10Script}'
    test ! -e "$task10_stamp"
    ! grep -Fq $'defaults\twrite\t' "$TASK10_LOG"

    task10_new_case missing-iterm-key
    rm "$TASK10_FAKE_STATE/iterm-key-metadata"
    task10_run_fail '${common.task10Script}'
    test ! -e "$task10_stamp"
    ! grep -Fq $'defaults\twrite\t' "$TASK10_LOG"

    # Failure in the first updater never starts the second updater or stamps.
    task10_new_case first-updater-failure
    export TASK10_FAIL_AT=devonthink-update
    task10_run_fail '${common.task10Script}'
    test ! -e "$task10_stamp"
    ! grep -Fq $'defaults\twrite\tcom.googlecode.iterm2\t' "$TASK10_LOG"

    # Failure in the second updater preserves the old stamp; retry succeeds.
    task10_new_case second-updater-failure
    mkdir -p "$(dirname "$task10_stamp")"
    printf '%s' stale-digest > "$task10_stamp"
    export TASK10_FAIL_AT=iterm-update
    task10_run_fail '${common.task10Script}'
    test "$(cat "$task10_stamp")" = stale-digest
    grep -Fq $'defaults\twrite\tcom.devon-technologies.think\t' "$TASK10_LOG"
    grep -Fq $'defaults\twrite\tcom.googlecode.iterm2\t' "$TASK10_LOG"
    unset TASK10_FAIL_AT
    : > "$TASK10_LOG"
    task10_run_ok '${common.task10Script}'
    test "$(cat "$task10_stamp")" = '${common.task10Digest}'
    task10_assert_exact_app_calls

    # Readback failure also preserves the old digest and retries cleanly.
    task10_new_case verification-failure
    mkdir -p "$(dirname "$task10_stamp")"
    printf '%s' old-digest > "$task10_stamp"
    export TASK10_FAIL_AT=iterm-verify
    task10_run_fail '${common.task10Script}'
    test "$(cat "$task10_stamp")" = old-digest
    unset TASK10_FAIL_AT
    : > "$TASK10_LOG"
    task10_run_ok '${common.task10Script}'
    test "$(cat "$task10_stamp")" = '${common.task10Digest}'

    # Failed atomic replacement preserves the old stamp and removes its temp.
    task10_new_case rename-failure
    mkdir -p "$(dirname "$task10_stamp")"
    printf '%s' '${common.task10Digest}' > "$task10_stamp"
    export TASK10_EXPECTED_MODEL='${common.alternateModelData.syncInputs.model}'
    export TASK10_EXPECTED_URL='${common.alternateModelData.syncInputs.chatUrl}'
    export TASK10_FAIL_AT=rename
    task10_run_fail '${common.task10ChangedScript}'
    test "$(cat "$task10_stamp")" = '${common.task10Digest}'
    test -z "$(find "$(dirname "$task10_stamp")" -name 'model-sync-v1.sha256.tmp.*' -print)"
    grep -Fq $'mv\t-fT\t--\t' "$TASK10_LOG"
    grep -Fq $'rm\t-f\t--\t' "$TASK10_LOG"

    unset TASK10_FAIL_AT
    : > "$TASK10_LOG"
    task10_run_ok '${common.task10ChangedScript}'
    test "$(cat "$task10_stamp")" = '${common.task10ChangedDigest}'
    test -z "$(find "$(dirname "$task10_stamp")" -name 'model-sync-v1.sha256.tmp.*' -print)"

    touch "$out"
  ''
