{
  darwinConfigurations,
  pkgs,
}:

let
  inherit (pkgs) lib;
  activation =
    darwinConfigurations.hera.config.home-manager.users.johnw.home.activation.claudeMemRealClaude;
  pin = import ../../config/claude-mem-pin.nix { inherit pkgs; };
  failingTool = pkgs.writeShellScript "claude-mem-failing-tool" ''
    exit 72
  '';
  failingMove = pkgs.writeShellScript "claude-mem-failing-move" ''
    [ "$#" -eq 4 ] || exit 74
    printf '%s\n' "$3" >"''${CLAUDE_MEM_MOVE_LOG:?}"
    exit 73
  '';
  recordingChgrp = pkgs.writeShellScript "claude-mem-recording-chgrp" ''
    [ "$#" -eq 2 ] || exit 76
    printf '%s\n' "$@" >"''${CLAUDE_MEM_CHGRP_LOG:?}"
    ${pkgs.coreutils}/bin/stat -c '%d:%i' "$2" >"''${CLAUDE_MEM_CHGRP_ID_LOG:?}"
    exec ${pkgs.coreutils}/bin/chgrp "$@"
  '';
  recordingMktemp = pkgs.writeShellScript "claude-mem-recording-mktemp" ''
    temporary="$(${pkgs.coreutils}/bin/mktemp "$@")"
    printf '%s\n' "$temporary" >"''${CLAUDE_MEM_MKTEMP_LOG:?}"
    ${pkgs.coreutils}/bin/stat -c '%d:%i' "$temporary" >"''${CLAUDE_MEM_MKTEMP_ID_LOG:?}"
    printf '%s\n' "$temporary"
  '';
  signalingMktemp = pkgs.writeShellScript "claude-mem-signaling-mktemp" ''
    temporary="$(${pkgs.coreutils}/bin/mktemp "$@")"
    printf '%s\n' "$temporary" >"''${CLAUDE_MEM_SIGNAL_TEMP_LOG:?}"
    printf '%s\n' "$temporary"
    kill -TERM "$PPID"
  '';
  pinWithFailingTool = import ../../config/claude-mem-pin.nix {
    inherit pkgs;
    tools.chmod = failingTool;
  };
  pinWithFailingMove = import ../../config/claude-mem-pin.nix {
    inherit pkgs;
    tools.mv = failingMove;
  };
  pinWithMetadataProbe = import ../../config/claude-mem-pin.nix {
    inherit pkgs;
    tools = {
      chgrp = recordingChgrp;
      mktemp = recordingMktemp;
    };
  };
  pinWithSignalProbe = import ../../config/claude-mem-pin.nix {
    inherit pkgs;
    tools.mktemp = signalingMktemp;
  };
  dryRunProbe = import ../../config/claude-mem-pin.nix {
    inherit pkgs;
    tools = {
      jq = failingTool;
      mktemp = failingTool;
    };
  };
in
assert activation.after == [ "writeBoundary" ];
assert activation.before == [ ];
assert lib.hasInfix "/bin/claude-mem-pin" activation.data;
assert lib.hasInfix ".claude-mem/settings.json" activation.data;
assert lib.hasInfix "/bin/claude-real" activation.data;
assert lib.hasInfix ''"''${DRY_RUN_CMD:-}"'' activation.data;
pkgs.runCommand "claude-mem-pin-contract" { } ''
  fail() {
    echo "claude-mem-pin test: $1" >&2
    exit 1
  }
  make_case() {
    case_directory="$work/$1"
    settings="$case_directory/settings.json"
    ${pkgs.coreutils}/bin/mkdir -p "$case_directory"
  }
  remember() {
    before="$work/$1.before"
    ${pkgs.coreutils}/bin/cp "$settings" "$before"
  }
  assert_unchanged() {
    ${pkgs.diffutils}/bin/cmp -s "$before" "$settings" \
      || fail "$1 changed settings"
  }
  assert_no_temporary() {
    for candidate in "$settings".??????; do
      [ ! -e "$candidate" ] && [ ! -L "$candidate" ] \
        || fail "$1 leaked temporary state"
    done
  }
  run_failure() {
    label=$1
    expected=$2
    shift 2
    status=0
    "$@" >"$work/$label.stdout" 2>"$work/$label.stderr" || status=$?
    [ "$status" -eq "$expected" ] \
      || fail "$label returned $status instead of $expected"
  }
  run_any_failure() {
    label=$1
    shift
    status=0
    "$@" >"$work/$label.stdout" 2>"$work/$label.stderr" || status=$?
    [ "$status" -ne 0 ] || fail "$label unexpectedly succeeded"
  }

  work="$TMPDIR/claude mem pin cases"
  target="/nix/store/example claude/bin/claude-real"
  ${pkgs.coreutils}/bin/mkdir -p "$work"

  make_case absent
  ${dryRunProbe}/bin/claude-mem-pin "$settings" "$target" "" >"$work/absent.stdout"
  [ ! -s "$work/absent.stdout" ] || fail "absent emitted output"
  [ ! -e "$settings" ] && [ ! -L "$settings" ] \
    || fail "absent created settings"
  assert_no_temporary absent

  make_case non-regular-directory
  ${pkgs.coreutils}/bin/mkdir "$settings"
  run_failure non-regular-directory 1 \
    ${dryRunProbe}/bin/claude-mem-pin "$settings" "$target" ""
  [ -d "$settings" ] && [ ! -L "$settings" ] \
    || fail "non-regular-directory changed settings"
  assert_no_temporary non-regular-directory

  make_case non-regular-fifo
  ${pkgs.coreutils}/bin/mkfifo "$settings"
  run_failure non-regular-fifo 1 \
    ${dryRunProbe}/bin/claude-mem-pin "$settings" "$target" ""
  [ -p "$settings" ] || fail "non-regular-fifo changed settings"
  assert_no_temporary non-regular-fifo

  make_case malformed
  printf '%s\n' '{not-json' >"$settings"
  remember malformed
  run_any_failure malformed ${pin}/bin/claude-mem-pin "$settings" "$target" ""
  assert_unchanged malformed
  assert_no_temporary malformed

  make_case symlink
  target_settings="$case_directory/target.json"
  printf '%s\n' '{"CLAUDE_CODE_PATH":"/old"}' >"$target_settings"
  ${pkgs.coreutils}/bin/ln -s target.json "$settings"
  before="$work/symlink.before"
  ${pkgs.coreutils}/bin/cp "$target_settings" "$before"
  run_failure symlink 1 ${pin}/bin/claude-mem-pin "$settings" "$target" ""
  [ -L "$settings" ] || fail "symlink replaced the settings link"
  [ "$(${pkgs.coreutils}/bin/readlink "$settings")" = target.json ] \
    || fail "symlink changed the settings link target"
  ${pkgs.diffutils}/bin/cmp -s "$before" "$target_settings" \
    || fail "symlink changed the settings target"
  assert_no_temporary symlink

  make_case unwritable
  printf '%s\n' '{"CLAUDE_CODE_PATH":"/old"}' >"$settings"
  remember unwritable
  ${pkgs.coreutils}/bin/chmod 0555 "$case_directory"
  status=0
  ${pin}/bin/claude-mem-pin "$settings" "$target" "" \
    >"$work/unwritable.stdout" 2>"$work/unwritable.stderr" || status=$?
  ${pkgs.coreutils}/bin/chmod 0755 "$case_directory"
  [ "$status" -ne 0 ] || fail "unwritable unexpectedly succeeded"
  assert_unchanged unwritable
  assert_no_temporary unwritable

  make_case tool-failure
  printf '%s\n' '{"CLAUDE_CODE_PATH":"/old"}' >"$settings"
  remember tool-failure
  run_failure tool-failure 72 \
    ${pinWithFailingTool}/bin/claude-mem-pin "$settings" "$target" ""
  assert_unchanged tool-failure
  assert_no_temporary tool-failure

  make_case move-failure
  printf '%s\n' '{"CLAUDE_CODE_PATH":"/old"}' >"$settings"
  remember move-failure
  move_log="$work/move-source"
  status=0
  CLAUDE_MEM_MOVE_LOG="$move_log" \
    ${pinWithFailingMove}/bin/claude-mem-pin "$settings" "$target" "" \
    >"$work/move-failure.stdout" 2>"$work/move-failure.stderr" || status=$?
  [ "$status" -eq 73 ] || fail "move-failure returned $status instead of 73"
  temporary="$(${pkgs.coreutils}/bin/cat "$move_log")"
  [ "$(${pkgs.coreutils}/bin/dirname "$temporary")" = "$case_directory" ] \
    || fail "temporary file was not created beside settings"
  [ ! -e "$temporary" ] || fail "move-failure did not clean its temporary file"
  assert_unchanged move-failure
  assert_no_temporary move-failure

  make_case signal-cleanup
  printf '%s\n' '{"CLAUDE_CODE_PATH":"/old"}' >"$settings"
  remember signal-cleanup
  signal_log="$work/signal-temporary"
  status=0
  CLAUDE_MEM_SIGNAL_TEMP_LOG="$signal_log" \
    ${pinWithSignalProbe}/bin/claude-mem-pin "$settings" "$target" "" \
    >"$work/signal-cleanup.stdout" 2>"$work/signal-cleanup.stderr" || status=$?
  [ "$status" -eq 143 ] || fail "signal-cleanup returned $status instead of 143"
  temporary="$(${pkgs.coreutils}/bin/cat "$signal_log")"
  [ "$(${pkgs.coreutils}/bin/dirname "$temporary")" = "$case_directory" ] \
    || fail "signal-cleanup temporary file was not beside settings"
  [ ! -e "$temporary" ] || fail "signal-cleanup leaked temporary state"
  assert_unchanged signal-cleanup
  assert_no_temporary signal-cleanup

  make_case current
  printf '{"CLAUDE_CODE_PATH":"%s","retained":true}\n' "$target" >"$settings"
  remember current
  inode="$(${pkgs.coreutils}/bin/stat -c '%i' "$settings")"
  ${pin}/bin/claude-mem-pin "$settings" "$target" "" >"$work/current.stdout"
  [ ! -s "$work/current.stdout" ] || fail "current emitted update output"
  [ "$inode" = "$(${pkgs.coreutils}/bin/stat -c '%i' "$settings")" ] \
    || fail "current replaced settings"
  assert_unchanged current
  assert_no_temporary current

  make_case stale
  printf '%s\n' '{"CLAUDE_CODE_PATH":"/old","retained":true}' >"$settings"
  ${pkgs.coreutils}/bin/chmod 0640 "$settings"
  group="$(${pkgs.coreutils}/bin/stat -c '%g' "$settings")"
  chgrp_log="$work/stale-chgrp"
  chgrp_id_log="$work/stale-chgrp-id"
  mktemp_log="$work/stale-mktemp"
  mktemp_id_log="$work/stale-mktemp-id"
  CLAUDE_MEM_CHGRP_ID_LOG="$chgrp_id_log" \
    CLAUDE_MEM_CHGRP_LOG="$chgrp_log" \
    CLAUDE_MEM_MKTEMP_ID_LOG="$mktemp_id_log" \
    CLAUDE_MEM_MKTEMP_LOG="$mktemp_log" \
    ${pinWithMetadataProbe}/bin/claude-mem-pin "$settings" "$target" "" \
    >"$work/stale.stdout"
  ${pkgs.gnugrep}/bin/grep -Fx \
    "claude-mem: pinned CLAUDE_CODE_PATH -> $target" "$work/stale.stdout" >/dev/null \
    || fail "stale did not report its update"
  ${pkgs.jq}/bin/jq -e --arg target "$target" \
    '.CLAUDE_CODE_PATH == $target and .retained == true' "$settings" >/dev/null \
    || fail "stale did not preserve and update settings"
  [ "$(${pkgs.coreutils}/bin/stat -c '%a' "$settings")" = 640 ] \
    || fail "stale did not preserve settings mode"
  [ "$(${pkgs.coreutils}/bin/stat -c '%g' "$settings")" = "$group" ] \
    || fail "stale did not preserve settings group"
  [ "$(${pkgs.coreutils}/bin/wc -l <"$chgrp_log")" -eq 2 ] \
    || fail "stale did not invoke chgrp with exactly two arguments"
  reference="$(${pkgs.coreutils}/bin/head -n 1 "$chgrp_log")"
  temporary="$(${pkgs.coreutils}/bin/cat "$mktemp_log")"
  chgrp_destination="$(${pkgs.coreutils}/bin/tail -n 1 "$chgrp_log")"
  [ "$reference" = "--reference=$settings" ] \
    || fail "stale did not preserve group by reference"
  [ "$chgrp_destination" = "$temporary" ] \
    || fail "stale chgrp destination was not the mktemp path"
  [ "$chgrp_destination" != "$settings" ] \
    || fail "stale applied chgrp to settings instead of the temporary file"
  case "$chgrp_destination" in
    "$settings".??????) ;;
    *) fail "stale chgrp destination did not match the temporary naming contract" ;;
  esac
  [ "$(${pkgs.coreutils}/bin/cat "$chgrp_id_log")" = \
    "$(${pkgs.coreutils}/bin/cat "$mktemp_id_log")" ] \
    || fail "stale chgrp destination was not the mktemp file identity"
  [ "$(${pkgs.coreutils}/bin/dirname "$temporary")" = "$case_directory" ] \
    || fail "stale metadata temporary file was not beside settings"
  [ "$(${pkgs.coreutils}/bin/stat -c '%d:%i' "$settings")" = \
    "$(${pkgs.coreutils}/bin/cat "$mktemp_id_log")" ] \
    || fail "stale did not install the mktemp file identity"
  assert_no_temporary stale

  make_case dry-run
  printf '%s\n' '{"CLAUDE_CODE_PATH":"/old","retained":true}' >"$settings"
  remember dry-run
  ${dryRunProbe}/bin/claude-mem-pin "$settings" "$target" echo >"$work/dry-run.stdout"
  ${pkgs.gnugrep}/bin/grep -Fx \
    "Would pin claude-mem CLAUDE_CODE_PATH -> $target" "$work/dry-run.stdout" >/dev/null \
    || fail "dry-run did not report its intended update"
  assert_unchanged dry-run
  assert_no_temporary dry-run

  ${pkgs.coreutils}/bin/touch "$out"
''
