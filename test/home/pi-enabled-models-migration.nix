{
  lib,
  piPackage,
  pkgs,
}:

let
  piRoot = "${piPackage}/lib/node_modules/@earendil-works/pi-coding-agent";
  migration = ../../config/ai/pi-enabled-models-migration.mjs;
in
assert piPackage.pname == "pi";
pkgs.runCommand "pi-enabled-models-migration"
  {
    nativeBuildInputs = [
      pkgs.jq
      pkgs.nodejs_22
    ];
  }
  ''
    set -eu

    run_migration() {
      PI_CODING_AGENT_DIR="$1" \
        PI_OMLX_LOCAL_PROVIDER="''${2:-omlx-clio}" \
        PI_CODING_AGENT_ROOT=${lib.escapeShellArg piRoot} \
        node ${migration}
    }

    snapshot() {
      ${pkgs.coreutils}/bin/stat -c '%d:%i' "$1"
      ${pkgs.coreutils}/bin/sha256sum "$1"
    }

    absent="$TMPDIR/absent"
    mkdir "$absent"
    run_migration "$absent"
    test ! -e "$absent/settings.json"
    test ! -e "$absent/settings.json.lock"

    empty="$TMPDIR/empty"
    mkdir "$empty"
    printf '%s\n' '{"enabledModels":[]}' >"$empty/settings.json"
    snapshot "$empty/settings.json" >"$empty.before"
    run_migration "$empty"
    snapshot "$empty/settings.json" >"$empty.after"
    cmp "$empty.before" "$empty.after"
    test ! -e "$empty/settings.json.lock"

    current="$TMPDIR/current"
    mkdir "$current"
    printf '%s\n' '{"enabledModels":["anthropic/*","factory/*"]}' >"$current/settings.json"
    snapshot "$current/settings.json" >"$current.before"
    run_migration "$current"
    snapshot "$current/settings.json" >"$current.after"
    cmp "$current.before" "$current.after"
    test ! -e "$current/settings.json.lock"

    no_scope="$TMPDIR/no-scope"
    mkdir "$no_scope"
    printf '%s\n' '{"theme":"dark"}' >"$no_scope/settings.json"
    snapshot "$no_scope/settings.json" >"$no_scope.before"
    run_migration "$no_scope"
    snapshot "$no_scope/settings.json" >"$no_scope.after"
    cmp "$no_scope.before" "$no_scope.after"
    test ! -e "$no_scope/settings.json.lock"

    legacy="$TMPDIR/legacy"
    mkdir -p "$legacy/.pi"
    printf '%s\n' \
      '{"theme":"dark","enabledModels":["anthropic/*","factory/*","omlx/qwen","openai/gpt","omlx/deepseek"]}' \
      >"$legacy/settings.json"
    printf '%s\n' '{"enabledModels":["omlx/project-must-not-change"]}' \
      >"$legacy/.pi/settings.json"
    snapshot "$legacy/.pi/settings.json" >"$legacy.project.before"
    run_migration "$legacy"
    jq -e '
      .theme == "dark" and
      .enabledModels == [
        "anthropic/*",
        "factory/*",
        "omlx-clio/qwen",
        "omlx-hera/qwen",
        "openai/gpt",
        "omlx-clio/deepseek",
        "omlx-hera/deepseek"
      ]
    ' "$legacy/settings.json" >/dev/null
    snapshot "$legacy/.pi/settings.json" >"$legacy.project.after"
    cmp "$legacy.project.before" "$legacy.project.after"

    legacy_hera="$TMPDIR/legacy-hera"
    mkdir "$legacy_hera"
    printf '%s\n' \
      '{"enabledModels":["anthropic/*","omlx/qwen","openai/gpt"]}' \
      >"$legacy_hera/settings.json"
    run_migration "$legacy_hera" omlx-hera
    jq -e '
      .enabledModels == [
        "anthropic/*",
        "omlx-hera/qwen",
        "omlx-clio/qwen",
        "openai/gpt",
        "factory/*"
      ]
    ' "$legacy_hera/settings.json" >/dev/null

    snapshot "$legacy/settings.json" >"$legacy.rerun.before"
    run_migration "$legacy"
    snapshot "$legacy/settings.json" >"$legacy.rerun.after"
    cmp "$legacy.rerun.before" "$legacy.rerun.after"

    race="$TMPDIR/race"
    mkdir "$race"
    printf '%s\n' \
      '{"theme":"dark","enabledModels":["omlx/original"]}' \
      >"$race/settings.json"
    PI_AGENT_DIR="$race" \
      PI_MIGRATION=${migration} \
      PI_ROOT=${lib.escapeShellArg piRoot} \
      node --input-type=module <<'EOF'
    import { readFileSync, writeFileSync } from "node:fs";
    import { join } from "node:path";
    import { pathToFileURL } from "node:url";

    const agentDir = process.env.PI_AGENT_DIR;
    const settingsPath = join(agentDir, "settings.json");
    const lockedCurrent = JSON.stringify({
      theme: "light",
      enabledModels: ["anthropic/new", "omlx/concurrent"],
    });
    const { migrateEnabledModels } = await import(
      pathToFileURL(process.env.PI_MIGRATION).href
    );
    const changed = await migrateEnabledModels({
      agentDir,
      localProvider: "omlx-clio",
      piRoot: process.env.PI_ROOT,
      storage: {
        withLock(scope, transform) {
          if (scope !== "global") throw new Error("unexpected settings scope");
          const next = transform(lockedCurrent);
          if (next !== undefined) writeFileSync(settingsPath, next, "utf8");
        },
      },
    });
    if (!changed) throw new Error("locked migration reported no change");
    const actual = JSON.parse(readFileSync(settingsPath, "utf8"));
    const expected = [
      "anthropic/new",
      "omlx-clio/concurrent",
      "omlx-hera/concurrent",
      "factory/*",
    ];
    if (actual.theme !== "light" || JSON.stringify(actual.enabledModels) !== JSON.stringify(expected)) {
      throw new Error("migration did not transform the lock-protected current settings");
    }
    EOF

    mixed_case="$TMPDIR/mixed-case"
    mkdir "$mixed_case"
    printf '%s\n' \
      '{"enabledModels":["Factory/*","OMLX/Qwen","openai/gpt"]}' \
      >"$mixed_case/settings.json"
    run_migration "$mixed_case"
    jq -e \
      '.enabledModels == ["Factory/*","omlx-clio/Qwen","omlx-hera/Qwen","openai/gpt"]' \
      "$mixed_case/settings.json" >/dev/null

    vanished="$TMPDIR/vanished"
    mkdir "$vanished"
    printf '%s\n' '{"enabledModels":["omlx/original"]}' >"$vanished/settings.json"
    PI_AGENT_DIR="$vanished" \
      PI_MIGRATION=${migration} \
      PI_ROOT=${lib.escapeShellArg piRoot} \
      node --input-type=module <<'EOF'
    import { unlinkSync } from "node:fs";
    import { join } from "node:path";
    import { pathToFileURL } from "node:url";

    const agentDir = process.env.PI_AGENT_DIR;
    const settingsPath = join(agentDir, "settings.json");
    const { migrateEnabledModels } = await import(
      pathToFileURL(process.env.PI_MIGRATION).href
    );
    let failedClosed = false;
    try {
      await migrateEnabledModels({
        agentDir,
        localProvider: "omlx-clio",
        piRoot: process.env.PI_ROOT,
        storage: {
          withLock(scope, transform) {
            if (scope !== "global") throw new Error("unexpected settings scope");
            unlinkSync(settingsPath);
            transform(undefined);
          },
        },
      });
    } catch (error) {
      failedClosed = error instanceof Error && error.message.includes("disappeared");
    }
    if (!failedClosed) throw new Error("migration accepted a vanished settings file");
    EOF
    test ! -e "$vanished/settings.json"

    replaced="$TMPDIR/replaced"
    mkdir "$replaced"
    printf '%s\n' '{"enabledModels":["omlx/original"]}' >"$replaced/settings.json"
    PI_AGENT_DIR="$replaced" \
      PI_MIGRATION=${migration} \
      PI_ROOT=${lib.escapeShellArg piRoot} \
      node --input-type=module <<'EOF'
    import { readFileSync, renameSync, writeFileSync } from "node:fs";
    import { join } from "node:path";
    import { pathToFileURL } from "node:url";

    const agentDir = process.env.PI_AGENT_DIR;
    const settingsPath = join(agentDir, "settings.json");
    const replacementPath = join(agentDir, "replacement.json");
    const original = readFileSync(settingsPath, "utf8");
    const replacement = '{"enabledModels":["openai/replacement"]}\n';
    const { migrateEnabledModels } = await import(
      pathToFileURL(process.env.PI_MIGRATION).href
    );
    let failedClosed = false;
    try {
      await migrateEnabledModels({
        agentDir,
        localProvider: "omlx-clio",
        piRoot: process.env.PI_ROOT,
        storage: {
          withLock(scope, transform) {
            if (scope !== "global") throw new Error("unexpected settings scope");
            writeFileSync(replacementPath, replacement, { flag: "wx" });
            renameSync(replacementPath, settingsPath);
            transform(original);
          },
        },
      });
    } catch (error) {
      failedClosed = error instanceof Error && error.message.includes("changed during migration");
    }
    if (!failedClosed) throw new Error("migration accepted a replaced settings file");
    if (readFileSync(settingsPath, "utf8") !== replacement) {
      throw new Error("migration altered the replacement settings file");
    }
    EOF

    dedupe="$TMPDIR/dedupe"
    mkdir "$dedupe"
    printf '%s\n' \
      '{"enabledModels":["omlx-clio/a","omlx/a","other","factory/*","omlx-hera/a","omlx/a","other","factory/*"]}' \
      >"$dedupe/settings.json"
    run_migration "$dedupe"
    jq -e \
      '.enabledModels == ["omlx-clio/a","other","factory/*","omlx-hera/a","other"]' \
      "$dedupe/settings.json" >/dev/null

    missing_host="$TMPDIR/missing-host"
    mkdir "$missing_host"
    printf '%s\n' '{"enabledModels":["omlx/foo"]}' >"$missing_host/settings.json"
    snapshot "$missing_host/settings.json" >"$missing_host.before"
    ! PI_CODING_AGENT_DIR="$missing_host" \
      PI_CODING_AGENT_ROOT=${lib.escapeShellArg piRoot} \
      node ${migration} >/dev/null 2>&1
    snapshot "$missing_host/settings.json" >"$missing_host.after"
    cmp "$missing_host.before" "$missing_host.after"

    invalid="$TMPDIR/invalid"
    mkdir "$invalid"
    printf '%s\n' '{not-json' >"$invalid/settings.json"
    snapshot "$invalid/settings.json" >"$invalid.before"
    ! run_migration "$invalid" >/dev/null 2>&1
    snapshot "$invalid/settings.json" >"$invalid.after"
    cmp "$invalid.before" "$invalid.after"

    wrong_type="$TMPDIR/wrong-type"
    mkdir "$wrong_type"
    printf '%s\n' '{"enabledModels":"omlx/foo"}' >"$wrong_type/settings.json"
    snapshot "$wrong_type/settings.json" >"$wrong_type.before"
    ! run_migration "$wrong_type" >/dev/null 2>&1
    snapshot "$wrong_type/settings.json" >"$wrong_type.after"
    cmp "$wrong_type.before" "$wrong_type.after"

    symlink_case="$TMPDIR/symlink"
    mkdir "$symlink_case"
    printf '%s\n' '{"enabledModels":["omlx/foo"]}' >"$symlink_case/target.json"
    ln -s target.json "$symlink_case/settings.json"
    snapshot "$symlink_case/target.json" >"$symlink_case.before"
    ! run_migration "$symlink_case" >/dev/null 2>&1
    test -L "$symlink_case/settings.json"
    snapshot "$symlink_case/target.json" >"$symlink_case.after"
    cmp "$symlink_case.before" "$symlink_case.after"

    special="$TMPDIR/special"
    mkdir "$special"
    mkfifo "$special/settings.json"
    ! run_migration "$special" >/dev/null 2>&1
    test -p "$special/settings.json"

    dry_run="$TMPDIR/dry-run"
    mkdir "$dry_run"
    printf '%s\n' '{"enabledModels":["omlx/foo"]}' >"$dry_run/settings.json"
    snapshot "$dry_run/settings.json" >"$dry_run.before"
    DRY_RUN= run_migration "$dry_run"
    snapshot "$dry_run/settings.json" >"$dry_run.after"
    cmp "$dry_run.before" "$dry_run.after"
    test ! -e "$dry_run/settings.json.lock"

    locked="$TMPDIR/locked"
    mkdir "$locked"
    printf '%s\n' '{"enabledModels":["omlx/foo"]}' >"$locked/settings.json"
    node -e '
      const lockfile = require(process.argv[1]);
      const fs = require("node:fs");
      lockfile.lockSync(process.argv[2], { realpath: false });
      fs.writeFileSync(process.argv[3], "");
      setInterval(() => {}, 1000);
    ' \
      ${lib.escapeShellArg "${piRoot}/node_modules/proper-lockfile"} \
      "$locked/settings.json" \
      "$locked/ready" &
    lock_holder=$!
    cleanup_lock_holder() {
      kill "$lock_holder" 2>/dev/null || true
      wait "$lock_holder" 2>/dev/null || true
    }
    trap cleanup_lock_holder EXIT HUP INT TERM
    while [ ! -e "$locked/ready" ]; do
      kill -0 "$lock_holder"
    done
    snapshot "$locked/settings.json" >"$locked.before"
    ! run_migration "$locked" >/dev/null 2>&1
    snapshot "$locked/settings.json" >"$locked.after"
    cmp "$locked.before" "$locked.after"
    cleanup_lock_holder
    trap - EXIT HUP INT TERM

    touch "$out"
  ''
