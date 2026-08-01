{
  pkgs,
  src,
  homeManagerLib,
}:

let
  inherit (pkgs) lib;
  homeManagerAwareLib = lib // {
    inherit (homeManagerLib) hm;
  };

  preflightFactory = import "${src}/config/fleet/preflight.nix" {
    lib = homeManagerAwareLib;
    inherit pkgs;
  };
  piProfileMigrationFactory = import "${src}/config/pi-profile-migration.nix" {
    lib = homeManagerAwareLib;
    inherit pkgs;
  };
  retiredMcpCleanupFactory = import "${src}/config/fleet/retired-mcp-cleanup.nix" {
    lib = homeManagerAwareLib;
    inherit pkgs;
  };
  piProfileMigration = piProfileMigrationFactory { root = ".config/pi"; };
  piAgentProfileMigration = piProfileMigrationFactory {
    root = ".config/pi/agent";
    compatibilityRoot = ".config/pi";
  };
  retiredMcpCleanup = retiredMcpCleanupFactory {
    homeDirectory = "/unused";
    retiredServers = [ "anvil" ];
    retiredManifestMcpItems = [
      "anvil"
      "anvil-tools"
    ];
    retiredManifestSkillItems = [ "anvil" ];
    codexRoots = [
      ".config/codex"
      ".config/codex-explicit"
      ".config/codex-inline"
      ".config/codex-sole"
    ];
    claudeRoots = [
      ".config/claude/personal"
      ".config/claude/positron"
    ];
    piRoots = [ ".config/pi/agent" ];
    manifestRoots = [
      ".config/claude/personal"
      ".config/claude/positron"
      ".config/codex"
      ".config/factory"
      ".config/opencode"
    ];
  };
  # Managed-file preflight contract: collision, permission, and symlink safety.
  task9PreflightWithPi = preflightFactory {
    newPaths = [
      ".config/claude/personal/agents/new.md"
      ".config/claude/personal/agents/retained.md"
    ];
    piGuard = {
      path = ".config/pi/agent/mcp.json";
      forbiddenKeys = [
        "mcpServers"
        "imports"
      ];
    };
    legacyPiGuardPath = ".pi/agent/mcp.json";
  };
  task9PreflightWithoutPi = preflightFactory {
    newPaths = [
      ".config/claude/personal/agents/new.md"
      ".config/claude/personal/agents/retained.md"
    ];
  };
  task9PiLeafPreflight = preflightFactory {
    newPaths = [ ".config/pi/agent/agents/bash-reviewer.md" ];
  };
  task9PiKeybindingsPreflight = preflightFactory {
    newPaths = [ ".config/pi/agent/keybindings.json" ];
  };
  task9SharedLeafPreflight = preflightFactory {
    newPaths = [
      ".agents/skills/nix-managed/SKILL.md"
      ".claude/agents/nix-managed.md"
      ".codex/agents/nix-managed.md"
      ".config/claude/personal/agents/nix-managed.md"
      ".config/claude/positron/agents/nix-managed.md"
      ".config/codex/agents/nix-managed.md"
      ".config/factory/droids/nix-managed.md"
      ".config/opencode/agents/nix-managed.md"
      ".config/pi/agent/agents/nix-managed.md"
    ];
  };
  task9StoreAliasEscape = pkgs.runCommand "task9-store-alias-escape" { } ''
    mkdir -p "$out"
    ln -s /tmp/task9-ai-preflight-store-escape "$out/personal"
  '';
  task9RetainedStoreLeaf = pkgs.writeText "task9-retained-leaf" "retained";
  writePreflightScript =
    name: preflight:
    pkgs.writeShellScript name ''
      set -euo pipefail
      ${preflight.script}
    '';
  task9PreflightScript = writePreflightScript "task9-ai-preflight" task9PreflightWithPi;
  task9PreflightBoundedScript = pkgs.writeShellScript "task9-ai-preflight-bounded" ''
    exec ${pkgs.coreutils}/bin/timeout --kill-after=1 30 ${task9PreflightScript}
  '';
  task9PreflightNoPiScript = writePreflightScript "task9-ai-preflight-no-pi" task9PreflightWithoutPi;
  task9PiLeafPreflightScript = writePreflightScript "task9-ai-pi-leaf-preflight" task9PiLeafPreflight;
  task9PiKeybindingsPreflightScript = writePreflightScript "task9-ai-pi-keybindings-preflight" task9PiKeybindingsPreflight;
  task9SharedLeafPreflightScript = writePreflightScript "task9-ai-shared-leaf-preflight" task9SharedLeafPreflight;
  task9PiProfileMigrationScript = pkgs.writeShellScript "task9-ai-pi-profile-migration" ''
    set -euo pipefail
    run() {
      if [[ ! -v DRY_RUN ]]; then
        "$@"
      fi
    }
    ${piProfileMigration.script}
  '';
  task9PiLegacyRootScript = pkgs.writeShellScript "task9-ai-pi-legacy-root" ''
    set -euo pipefail
    run() {
      if [[ ! -v DRY_RUN ]]; then
        "$@"
      fi
    }
    ${piAgentProfileMigration.legacyRootScript}
  '';
  task9PiAgentProfileMigrationScript = pkgs.writeShellScript "task9-ai-pi-agent-profile-migration" ''
    set -euo pipefail
    run() {
      if [[ ! -v DRY_RUN ]]; then
        "$@"
      fi
    }
    ${piAgentProfileMigration.script}
  '';
  invalidPreflightProbe = builtins.tryEval (preflightFactory {
    newPaths = [ ".config/not-a-managed-ai-leaf" ];
  });
  sherlockAncestorProbe = builtins.tryEval (preflightFactory {
    newPaths = [ ".claude/skills/sherlock" ];
  });
in
assert
  builtins.attrNames task9PreflightWithPi == [
    "activation"
    "script"
  ];
assert
  builtins.attrNames piProfileMigration == [
    "activation"
    "legacyRootActivation"
    "legacyRootScript"
    "script"
  ];
assert
  builtins.attrNames retiredMcpCleanup == [
    "activation"
    "planJson"
    "program"
    "script"
  ];
assert task9PreflightWithPi.activation.before == [ "checkLinkTargets" ];
assert task9PreflightWithPi.activation.after == [ ];
assert piProfileMigration.activation.before == [ "linkGeneration" ];
assert piProfileMigration.activation.after == [ "writeBoundary" ];
assert piProfileMigration.legacyRootActivation.before == [ "linkGeneration" ];
assert piProfileMigration.legacyRootActivation.after == [ "aiPiProfileMigration" ];
assert retiredMcpCleanup.activation.before == [ ];
assert retiredMcpCleanup.activation.after == [ "linkGeneration" ];
assert lib.hasInfix "run " (builtins.unsafeDiscardStringContext retiredMcpCleanup.activation.data);
assert lib.hasInfix ".pi/agent" piProfileMigration.script;
assert lib.hasInfix ".config/pi" piProfileMigration.script;
assert lib.hasInfix "--archive --no-preserve=links --update=none" piProfileMigration.script;
assert lib.hasInfix ".pi-legacy-v1" piProfileMigration.legacyRootScript;
assert lib.hasInfix "mv -T" piProfileMigration.legacyRootScript;
assert !(lib.hasInfix "cp " piProfileMigration.legacyRootScript);
assert lib.hasInfix ".config/pi/agent" piAgentProfileMigration.script;
assert lib.hasInfix ".config/pi/agent/mcp.json" task9PreflightWithPi.script;
assert lib.hasInfix ".pi/agent/mcp.json" task9PreflightWithPi.script;
assert !(lib.hasInfix ".config/pi/agent/mcp.json" task9PreflightWithoutPi.script);
assert !(lib.hasInfix ".pi/agent/mcp.json" task9PreflightWithoutPi.script);
assert
  !(lib.any (fragment: lib.hasInfix fragment task9PreflightWithPi.script) [
    "adoption-state"
    "ledger"
    "manifest"
    "ownership"
    "receipt"
    "stamp"
  ]);
assert !invalidPreflightProbe.success;
assert !sherlockAncestorProbe.success;

pkgs.runCommand "ai-managed-preflight"
  {
    nativeBuildInputs = [
      pkgs.coreutils
      pkgs.findutils
      pkgs.jq
      pkgs.python3
      pkgs.yq
    ]
    ++ lib.optional pkgs.stdenv.isDarwin pkgs.darwin.xattr;
  }
  ''
    preflight_root="$TMPDIR/task9-preflight"
    mkdir -p "$preflight_root"
    digest_script="$TMPDIR/task9-tree-digest.py"
    cat > "$digest_script" <<'PY'
    import hashlib
    import os
    import stat
    import sys
    from pathlib import Path

    root = Path(sys.argv[1])
    records = []
    for directory, directories, files in os.walk(root, followlinks=False):
        base = Path(directory)
        for name in sorted(directories + files):
            path = base / name
            relative = path.relative_to(root).as_posix()
            mode = path.lstat().st_mode
            if stat.S_ISLNK(mode):
                payload = os.fsencode(os.readlink(path))
                kind = b"l"
            elif stat.S_ISREG(mode):
                payload = path.read_bytes()
                kind = b"f"
            elif stat.S_ISDIR(mode):
                payload = b""
                kind = b"d"
            else:
                payload = b""
                kind = b"o"
            records.append(
                relative.encode()
                + b"\0"
                + kind
                + b"\0"
                + oct(stat.S_IMODE(mode)).encode()
                + b"\0"
                + hashlib.sha256(payload).hexdigest().encode()
                + b"\0"
            )
    print(hashlib.sha256(b"".join(sorted(records))).hexdigest())
    PY

    new_path=".config/claude/personal/agents/new.md"
    retained_path=".config/claude/personal/agents/retained.md"
    removed_path=".config/claude/personal/agents/removed.md"
    pi_leaf_path=".config/pi/agent/agents/bash-reviewer.md"
    pi_keybindings_path=".config/pi/agent/keybindings.json"
    legacy_claude=".local/bin/claude"

    make_leaf() {
      root=$1
      path=$2
      value=$3
      mkdir -p "$root/$(dirname "$path")"
      printf '%s' "$value" > "$root/$path"
    }

    link_old_leaf() {
      path=$1
      mkdir -p "$case_home/$(dirname "$path")"
      ln -s "$old_files/$path" "$case_home/$path"
    }

    setup_empty_case() {
      label=$1
      case_root="$preflight_root/$label"
      case_home="$case_root/home"
      old_gen=
      old_files=
      old_override=
      mkdir -p "$case_home"
    }

    setup_old_case() {
      setup_empty_case "$1"
      old_gen="$case_root/old-generation"
      old_files="$case_root/old-files"
      mkdir -p "$old_gen" "$old_files"
      ln -s "$old_files" "$old_gen/home-files"

      make_leaf "$old_files" "$retained_path" retained
      make_leaf "$old_files" "$removed_path" removed
      make_leaf "$old_files" "$legacy_claude" legacy
      symlink_leaf=".config/claude/personal/agents/symlinked.md"
      symlink_source="$case_root/symlink-source.md"
      printf '%s' symlinked > "$symlink_source"
      mkdir -p "$old_files/$(dirname "$symlink_leaf")"
      ln -s "$symlink_source" "$old_files/$symlink_leaf"
      make_leaf "$old_files" ".claude/skills/sherlock/SKILL.md" sherlock
      make_leaf "$old_files" ".claude/skills/sherlock/sherlock" sherlock-bin

      mkdir -p "$case_home/$(dirname "$retained_path")"
      ln -s ${task9RetainedStoreLeaf} "$case_home/$retained_path"
      link_old_leaf "$removed_path"
      link_old_leaf "$legacy_claude"
      link_old_leaf "$symlink_leaf"
    }

    setup_pi_alias_case() {
      setup_empty_case "$1"
      old_gen="$case_root/old-generation"
      old_files="$case_root/old-files"
      pi_root="$case_root/pi-root"
      mkdir -p \
        "$old_gen" \
        "$old_files/.config/pi" \
        "$case_home/.config/pi" \
        "$pi_root"
      ln -s "$old_files" "$old_gen/home-files"
      ln -s "$pi_root" "$old_files/.config/pi/agent"
      ln -s "$old_files/.config/pi/agent" "$case_home/.config/pi/agent"
      make_leaf "$pi_root" "unmanaged-sibling.json" '{"kept":true}'
    }

    tree_digest() {
      python3 -I "$digest_script" "$case_root"
    }

    run_checked() {
      expected=$1
      label=$2
      fragment=$3
      script=$4
      old_mode=$5
      output="$TMPDIR/task9-$label.output"
      before="$(tree_digest)"
      set +e
      if [ "$old_mode" = absent ]; then
        env -u oldGenPath HOME="$case_home" "$script" >"$output" 2>&1
      else
        env oldGenPath="''${old_override:-$old_gen}" HOME="$case_home" \
          "$script" >"$output" 2>&1
      fi
      status=$?
      set -e
      after="$(tree_digest)"
      if [ "$before" != "$after" ]; then
        echo "Task 9 preflight case mutated its input tree: $label" >&2
        return 1
      fi
      if grep -Fq SECRET_SENTINEL "$output"; then
        echo "Task 9 preflight case leaked file content: $label" >&2
        return 1
      fi
      if [ "$status" -eq 124 ] || [ "$status" -eq 137 ]; then
        echo "Task 9 preflight case timed out: $label (status $status)" >&2
        return 1
      fi
      case "$script" in
        *task9-ai-pi-leaf-preflight | *task9-ai-pi-keybindings-preflight)
          expected_count=1
          expected_noun=path
          ;;
        *task9-ai-shared-leaf-preflight)
          expected_count=9
          expected_noun=paths
          ;;
        *)
          expected_count=2
          expected_noun=paths
          ;;
      esac
      expected_progress="Checking $expected_count Nix-managed AI leaf $expected_noun for blockers..."
      actual_progress="$(head -n 1 "$output")"
      if [ "$actual_progress" != "$expected_progress" ]; then
        echo "Task 9 preflight case omitted its progress message: $label" >&2
        sed 's/^/  /' "$output" >&2
        return 1
      fi
      diagnostics="$output.diagnostics"
      tail -n +2 "$output" > "$diagnostics"
      if [ "$expected" = pass ]; then
        if [ "$status" -ne 0 ] || [ -s "$diagnostics" ]; then
          echo "Task 9 preflight case should have passed without diagnostics: $label" >&2
          sed 's/^/  /' "$output" >&2
          return 1
        fi
      else
        case "$label" in
          first-adoption-collision | new-file)
            expected_output="$fragment: blocking leaf is a regular file: $case_home/$fragment"
            ;;
          new-directory | new-old-directory-shadow)
            expected_output="$fragment: blocking leaf is a directory: $case_home/$fragment"
            ;;
          new-valid-symlink | new-dangling-symlink | \
          retained-retargeted | retained-same-payload | retained-dangling)
            expected_output="$fragment: blocking leaf is a symlink outside the Nix store: $case_home/$fragment"
            ;;
          new-ancestor-file)
            expected_output="$new_path: blocking parent is a regular file: $case_home/.config/claude/personal/agents
    $retained_path: blocking parent is a regular file: $case_home/.config/claude/personal/agents"
            ;;
          new-readonly-parent)
            expected_output="$new_path: blocking parent is an unwritable directory: $case_home/.config/claude/personal/agents
    $retained_path: blocking parent is an unwritable directory: $case_home/.config/claude/personal/agents"
            ;;
          retained-readonly-parent)
            expected_output="$new_path: blocking parent is an unwritable directory: $case_home/.config/claude/personal/agents
    $retained_path: blocking parent is an unwritable directory: $case_home/.config/claude/personal/agents"
            ;;
          new-unsearchable-parent)
            expected_output="$new_path: blocking parent is an unsearchable directory: $case_home/.config/claude/personal/agents
    $retained_path: blocking parent is an unsearchable directory: $case_home/.config/claude/personal/agents"
            ;;
          new-missing-under-readonly-ancestor)
            expected_output="$new_path: blocking parent is an unwritable directory: $case_home/.config
    $retained_path: blocking parent is an unwritable directory: $case_home/.config"
            ;;
          new-dangling-parent)
            expected_output="$new_path: blocking parent is an unusable symlink: $case_home/.config/claude/personal/agents
    $retained_path: blocking parent is an unusable symlink: $case_home/.config/claude/personal/agents"
            ;;
          new-readonly-ancestor-symlink)
            expected_output="$new_path: blocking parent is a symlink to an unwritable directory: $case_home/.config/claude
    $retained_path: blocking parent is a symlink to an unwritable directory: $case_home/.config/claude"
            ;;
          new-store-parent | store-alias-with-writable-descendant)
            expected_output="$new_path: blocking parent is a symlink into the Nix store: $case_home/.config/claude
    $retained_path: blocking parent is a symlink into the Nix store: $case_home/.config/claude"
            ;;
          shared-pi-leaf-collision | pi-keybindings-collision)
            expected_output="$fragment: blocking leaf is a regular file: $case_home/$fragment"
            ;;
          aggregate-*)
            expected_output="$fragment"
            ;;
          retained-file)
            expected_output="$fragment: blocking leaf is a regular file: $case_home/$fragment"
            ;;
          pi-*)
            expected_output="$fragment: keep valid adapter JSON without top-level mcpServers or imports"
            ;;
          *)
            echo "Task 9 preflight case has no expected diagnostic: $label" >&2
            return 1
            ;;
        esac
        actual_output="$(<"$diagnostics")"
        if [ "$status" -eq 0 ] || [ "$actual_output" != "$expected_output" ]; then
          echo "Task 9 preflight case did not reject as expected: $label" >&2
          sed 's/^/  /' "$output" >&2
          return 1
        fi
      fi
    }

    setup_empty_case first-adoption
    run_checked pass first-adoption "" "${task9PreflightScript}" absent

    setup_empty_case first-adoption-collision
    make_leaf "$case_home" "$new_path" collision
    run_checked fail first-adoption-collision "$new_path" "${task9PreflightScript}" absent

    setup_empty_case aggregate-new-leaves
    make_leaf "$case_home" "$new_path" collision
    make_leaf "$case_home" "$retained_path" collision
    aggregate_output="$new_path: blocking leaf is a regular file: $case_home/$new_path
    $retained_path: blocking leaf is a regular file: $case_home/$retained_path"
    run_checked fail aggregate-new-leaves "$aggregate_output" "${task9PreflightScript}" absent

    setup_empty_case new-ancestor-file
    make_leaf "$case_home" ".config/claude/personal/agents" collision
    run_checked fail new-ancestor-file "$new_path" "${task9PreflightScript}" absent

    setup_empty_case new-readonly-parent
    mkdir -p "$case_home/.config/claude/personal/agents"
    chmod 0555 "$case_home/.config/claude/personal/agents"
    run_checked fail new-readonly-parent "$new_path" "${task9PreflightScript}" absent

    setup_empty_case existing-readonly-ancestor
    mkdir -p "$case_home/.config/claude/personal/agents"
    chmod 0555 "$case_home/.config"
    run_checked pass existing-readonly-ancestor "" "${task9PreflightScript}" absent

    setup_empty_case new-missing-under-readonly-ancestor
    mkdir -p "$case_home/.config"
    chmod 0555 "$case_home/.config"
    run_checked fail new-missing-under-readonly-ancestor "$new_path" \
      "${task9PreflightScript}" absent

    setup_empty_case new-unsearchable-parent
    mkdir -p "$case_home/.config/claude/personal/agents"
    chmod 0666 "$case_home/.config/claude/personal/agents"
    run_checked fail new-unsearchable-parent "$new_path" "${task9PreflightScript}" absent

    setup_empty_case new-writable-ancestor-symlink
    mkdir -p "$case_root/claude-root/personal/agents" "$case_home/.config"
    ln -s "$case_root/claude-root" "$case_home/.config/claude"
    run_checked pass new-writable-ancestor-symlink "" "${task9PreflightScript}" absent

    setup_empty_case new-readonly-ancestor-symlink
    mkdir -p "$case_root/claude-root/personal/agents" "$case_home/.config"
    chmod 0555 "$case_root/claude-root"
    ln -s "$case_root/claude-root" "$case_home/.config/claude"
    run_checked fail new-readonly-ancestor-symlink "$new_path" \
      "${task9PreflightScript}" absent

    setup_empty_case new-dangling-parent
    mkdir -p "$case_home/.config/claude/personal"
    ln -s "$case_root/missing" "$case_home/.config/claude/personal/agents"
    run_checked fail new-dangling-parent "$new_path" "${task9PreflightScript}" absent

    setup_empty_case new-store-parent
    mkdir -p "$case_home/.config"
    ln -s ${pkgs.coreutils} "$case_home/.config/claude"
    run_checked fail new-store-parent "$new_path" "${task9PreflightScript}" absent

    setup_empty_case store-alias-with-writable-descendant
    store_escape=/tmp/task9-ai-preflight-store-escape
    rm -rf "$store_escape"
    mkdir -p "$store_escape/agents" "$case_home/.config"
    ln -s ${task9StoreAliasEscape} "$case_home/.config/claude"
    run_checked fail store-alias-with-writable-descendant "$new_path" \
      "${task9PreflightScript}" absent
    rm -rf "$store_escape"

    setup_old_case new-old-directory-shadow
    mkdir -p "$old_files/$new_path" "$case_home/$new_path"
    run_checked fail new-old-directory-shadow "$new_path" "${task9PreflightScript}" present

    setup_empty_case missing-old-generation
    old_override="$case_root/missing-generation"
    run_checked pass missing-old-generation "" "${task9PreflightScript}" present

    setup_empty_case aggregate-missing-old-generation-parent
    old_override="$case_root/missing-generation"
    mkdir -p "$case_home/.config"
    chmod 0555 "$case_home/.config"
    aggregate_output="$new_path: blocking parent is an unwritable directory: $case_home/.config
    $retained_path: blocking parent is an unwritable directory: $case_home/.config"
    run_checked fail aggregate-missing-old-generation-parent "$aggregate_output" \
      "${task9PreflightScript}" present

    setup_empty_case missing-home-files
    old_gen="$case_root/old-generation"
    mkdir -p "$old_gen"
    run_checked pass missing-home-files "" "${task9PreflightScript}" present

    setup_empty_case old-home-files-not-directory
    old_gen="$case_root/old-generation"
    mkdir -p "$old_gen"
    make_leaf "$old_gen" home-files wrong-type
    run_checked pass old-home-files-not-directory "" "${task9PreflightScript}" present

    setup_old_case unreadable-old-files
    mkdir -p "$old_files/unreadable"
    chmod 000 "$old_files/unreadable"
    run_checked pass unreadable-old-files "" "${task9PreflightScript}" present

    setup_old_case aggregate-unreadable-old-files
    mkdir -p "$old_files/unreadable"
    chmod 000 "$old_files/unreadable"
    make_leaf "$case_home" "$new_path" collision
    make_leaf "$case_home" ".config/pi/agent/mcp.json" '{"imports":[]}'
    aggregate_output="$new_path: blocking leaf is a regular file: $case_home/$new_path
    .config/pi/agent/mcp.json: keep valid adapter JSON without top-level mcpServers or imports"
    run_checked fail aggregate-unreadable-old-files "$aggregate_output" \
      "${task9PreflightScript}" present

    setup_old_case all-three-classes
    run_checked pass all-three-classes "" "${task9PreflightScript}" present

    setup_old_case new-file
    make_leaf "$case_home" "$new_path" collision
    run_checked fail new-file "$new_path" "${task9PreflightScript}" present

    setup_old_case new-directory
    mkdir -p "$case_home/$new_path"
    run_checked fail new-directory "$new_path" "${task9PreflightScript}" present

    setup_old_case new-valid-symlink
    make_leaf "$case_root" unrelated target
    mkdir -p "$case_home/$(dirname "$new_path")"
    ln -s "$case_root/unrelated" "$case_home/$new_path"
    run_checked fail new-valid-symlink "$new_path" "${task9PreflightScript}" present

    setup_old_case new-dangling-symlink
    mkdir -p "$case_home/$(dirname "$new_path")"
    ln -s "$case_root/missing" "$case_home/$new_path"
    run_checked fail new-dangling-symlink "$new_path" "${task9PreflightScript}" present

    setup_old_case new-store-symlink
    mkdir -p "$case_home/$(dirname "$new_path")"
    ln -s ${pkgs.coreutils}/bin/true "$case_home/$new_path"
    run_checked pass new-store-symlink "" "${task9PreflightScript}" present

    setup_old_case new-dangling-store-symlink
    mkdir -p "$case_home/$(dirname "$new_path")"
    ln -s ${builtins.storeDir}/00000000000000000000000000000000-missing "$case_home/$new_path"
    run_checked pass new-dangling-store-symlink "" "${task9PreflightScript}" present

    setup_old_case new-relative-store-symlink
    mkdir -p "$case_home/$(dirname "$new_path")"
    relative_target="$(realpath --relative-to="$(dirname "$case_home/$new_path")" \
      ${pkgs.coreutils}/bin/true)"
    ln -s "$relative_target" "$case_home/$new_path"
    run_checked pass new-relative-store-symlink "" "${task9PreflightScript}" present

    setup_old_case new-relative-dangling-store-symlink
    mkdir -p "$case_home/$(dirname "$new_path")"
    relative_target="$(realpath -m --relative-to="$(dirname "$case_home/$new_path")" \
      ${builtins.storeDir}/00000000000000000000000000000000-missing)"
    ln -s "$relative_target" "$case_home/$new_path"
    run_checked pass new-relative-dangling-store-symlink "" \
      "${task9PreflightScript}" present

    setup_old_case retained-missing
    rm "$case_home/$retained_path"
    run_checked pass retained-missing "" "${task9PreflightScript}" present

    setup_old_case retained-readonly-parent
    mv "$case_home/.config/claude" "$case_root/claude-root"
    ln -s "$case_root/claude-root" "$case_home/.config/claude"
    chmod 0555 "$case_root/claude-root/personal/agents"
    run_checked fail retained-readonly-parent "$retained_path" "${task9PreflightScript}" present

    setup_old_case aggregate-old-missing
    rm "$case_home/$removed_path" "$case_home/$retained_path"
    run_checked pass aggregate-old-missing "" "${task9PreflightScript}" present

    setup_old_case retained-file
    rm "$case_home/$retained_path"
    make_leaf "$case_home" "$retained_path" replacement
    run_checked fail retained-file "$retained_path" "${task9PreflightScript}" present

    setup_old_case retained-retargeted
    make_leaf "$case_root" alternate different
    rm "$case_home/$retained_path"
    ln -s "$case_root/alternate" "$case_home/$retained_path"
    run_checked fail retained-retargeted "$retained_path" "${task9PreflightScript}" present

    setup_old_case retained-same-payload
    make_leaf "$case_root" alternate retained
    rm "$case_home/$retained_path"
    ln -s "$case_root/alternate" "$case_home/$retained_path"
    run_checked fail retained-same-payload "$retained_path" "${task9PreflightScript}" present

    setup_old_case retained-dangling
    rm "$case_home/$retained_path"
    ln -s "$case_root/missing" "$case_home/$retained_path"
    run_checked fail retained-dangling "$retained_path" "${task9PreflightScript}" present

    setup_old_case retained-store-symlink
    rm "$case_home/$retained_path"
    ln -s ${pkgs.coreutils}/bin/true "$case_home/$retained_path"
    run_checked pass retained-store-symlink "" "${task9PreflightScript}" present

    setup_old_case retained-dangling-store-symlink
    rm "$case_home/$retained_path"
    ln -s ${builtins.storeDir}/00000000000000000000000000000000-missing \
      "$case_home/$retained_path"
    run_checked pass retained-dangling-store-symlink "" "${task9PreflightScript}" present

    setup_old_case removed-missing
    rm "$case_home/$removed_path"
    run_checked pass removed-missing "" "${task9PreflightScript}" present

    setup_old_case removed-symlink-leaf-missing
    rm "$case_home/$symlink_leaf"
    run_checked pass removed-symlink-leaf-missing "" "${task9PreflightScript}" present

    setup_old_case removed-file
    rm "$case_home/$removed_path"
    make_leaf "$case_home" "$removed_path" replacement
    run_checked pass removed-file "" "${task9PreflightScript}" present

    setup_old_case removed-dangling
    rm "$case_home/$removed_path"
    ln -s "$case_root/missing" "$case_home/$removed_path"
    run_checked pass removed-dangling "" "${task9PreflightScript}" present

    setup_old_case removed-retargeted
    make_leaf "$case_root" alternate removed
    rm "$case_home/$removed_path"
    ln -s "$case_root/alternate" "$case_home/$removed_path"
    run_checked pass removed-retargeted "" "${task9PreflightScript}" present

    setup_old_case legacy-claude-missing
    rm "$case_home/$legacy_claude"
    run_checked pass legacy-claude-missing "" "${task9PreflightScript}" present

    setup_old_case legacy-claude-retargeted
    make_leaf "$case_root" alternate legacy
    rm "$case_home/$legacy_claude"
    ln -s "$case_root/alternate" "$case_home/$legacy_claude"
    run_checked pass legacy-claude-retargeted "" "${task9PreflightScript}" present

    setup_old_case legacy-readonly-parent
    chmod 0555 "$case_home/.local/bin"
    run_checked pass legacy-readonly-parent "" "${task9PreflightScript}" present

    setup_empty_case shared-agent-directories
    for sibling in \
      ".agents/skills/user-owned/notes.md" \
      ".claude/agents/user-owned.md" \
      ".codex/agents/user-owned.md" \
      ".config/claude/personal/agents/user-owned.md" \
      ".config/claude/positron/agents/user-owned.md" \
      ".config/codex/agents/user-owned.md" \
      ".config/factory/droids/user-owned.md" \
      ".config/opencode/agents/user-owned.md" \
      ".config/pi/agent/agents/user-owned.md"
    do
      make_leaf "$case_home" "$sibling" user-owned
    done
    run_checked pass shared-agent-directories "" "${task9SharedLeafPreflightScript}" absent

    setup_empty_case shared-pi-real-directory
    make_leaf "$case_home" ".config/pi/agent/unmanaged-sibling.json" '{"kept":true}'
    run_checked pass shared-pi-real-directory "" "${task9PiLeafPreflightScript}" absent

    setup_pi_alias_case shared-pi-xdg-alias
    run_checked pass shared-pi-xdg-alias "" "${task9PiLeafPreflightScript}" present

    setup_pi_alias_case shared-pi-leaf-collision
    make_leaf "$pi_root" "agents/bash-reviewer.md" unmanaged
    run_checked fail shared-pi-leaf-collision "$pi_leaf_path" \
      "${task9PiLeafPreflightScript}" present

    setup_empty_case pi-keybindings-collision
    make_leaf "$case_home" "$pi_keybindings_path" unmanaged
    run_checked fail pi-keybindings-collision "$pi_keybindings_path" \
      "${task9PiKeybindingsPreflightScript}" absent

    write_pi() {
      value=$1
      mkdir -p "$case_home/.config/pi/agent"
      printf '%s' "$value" > "$case_home/.config/pi/agent/mcp.json"
    }

    write_legacy_pi() {
      value=$1
      mkdir -p "$case_home/.pi/agent"
      printf '%s' "$value" > "$case_home/.pi/agent/mcp.json"
    }

    setup_empty_case pi-empty-object
    write_pi '{}'
    run_checked pass pi-empty-object "" "${task9PreflightScript}" absent

    setup_empty_case pi-benign-nested
    write_pi '{"settings":{"mcpServers":{}},"unknown":{"imports":[]}}'
    run_checked pass pi-benign-nested "" "${task9PreflightScript}" absent

    setup_empty_case pi-legacy-benign
    write_legacy_pi '{}'
    run_checked pass pi-legacy-benign "" "${task9PreflightScript}" absent

    setup_empty_case pi-legacy-mcp-servers
    write_legacy_pi '{"mcpServers":null}'
    run_checked fail pi-legacy-mcp-servers ".pi/agent/mcp.json" \
      "${task9PreflightScript}" absent

    setup_empty_case aggregate-pi-both-roots-invalid
    write_pi '{"imports":[]}'
    write_legacy_pi '{"mcpServers":null}'
    aggregate_output="$(printf '%s\n%s' \
      '.config/pi/agent/mcp.json: keep valid adapter JSON without top-level mcpServers or imports' \
      '.pi/agent/mcp.json: keep valid adapter JSON without top-level mcpServers or imports')"
    run_checked fail aggregate-pi-both-roots-invalid "$aggregate_output" \
      "${task9PreflightScript}" absent

    setup_empty_case pi-benign-symlink
    make_leaf "$case_root" pi-settings '{}'
    mkdir -p "$case_home/.config/pi/agent"
    ln -s "$case_root/pi-settings" "$case_home/.config/pi/agent/mcp.json"
    run_checked pass pi-benign-symlink "" "${task9PreflightScript}" absent

    setup_empty_case pi-mcp-servers
    write_pi '{"mcpServers":null}'
    run_checked fail pi-mcp-servers ".config/pi/agent/mcp.json" "${task9PreflightScript}" absent

    setup_empty_case pi-imports
    write_pi '{"imports":[]}'
    run_checked fail pi-imports ".config/pi/agent/mcp.json" "${task9PreflightScript}" absent

    setup_empty_case pi-malformed
    write_pi '{SECRET_SENTINEL'
    run_checked fail pi-malformed ".config/pi/agent/mcp.json" "${task9PreflightScript}" absent

    setup_empty_case pi-fifo
    mkdir -p "$case_home/.config/pi/agent"
    mkfifo "$case_home/.config/pi/agent/mcp.json"
    run_checked fail pi-fifo ".config/pi/agent/mcp.json"       "${task9PreflightBoundedScript}" absent

    for pi_case in array string number true false null; do
      setup_empty_case "pi-$pi_case"
      case "$pi_case" in
        array) write_pi '[]' ;;
        string) write_pi '"text"' ;;
        number) write_pi '0' ;;
        true) write_pi 'true' ;;
        false) write_pi 'false' ;;
        null) write_pi 'null' ;;
      esac
      run_checked fail "pi-$pi_case" ".config/pi/agent/mcp.json" \
        "${task9PreflightScript}" absent
    done

    setup_empty_case non-pi-ignores-adapter
    write_pi '{"mcpServers":null}'
    run_checked pass non-pi-ignores-adapter "" "${task9PreflightNoPiScript}" absent

    migration_root="$TMPDIR/task9-pi-profile-migration"
    mkdir -p "$migration_root"

    migration_home="$migration_root/source-absent"
    mkdir -p "$migration_home"
    HOME="$migration_home" ${task9PiProfileMigrationScript}
    test ! -e "$migration_home/.config/pi"

    migration_home="$migration_root/dry-run"
    mkdir -p "$migration_home/.pi/agent"
    printf '%s' auth > "$migration_home/.pi/agent/auth.json"
    DRY_RUN=1 HOME="$migration_home" ${task9PiProfileMigrationScript}
    test ! -e "$migration_home/.config/pi"

    migration_home="$migration_root/dry-run-inverse-link"
    mkdir -p "$migration_home/.config" "$migration_home/.pi/agent"
    printf '%s' auth > "$migration_home/.pi/agent/auth.json"
    ln -s ../.pi "$migration_home/.config/pi"
    migration_dry_run_before="$(python3 -I "$digest_script" "$migration_home")"
    DRY_RUN=1 HOME="$migration_home" ${task9PiProfileMigrationScript}
    migration_dry_run_after="$(python3 -I "$digest_script" "$migration_home")"
    test "$migration_dry_run_before" = "$migration_dry_run_after"
    test -L "$migration_home/.config/pi"
    test ! -e "$migration_home/.config/.nix-pi-profile-migrated-v1"
    test ! -e "$migration_home/.config/.pi-profile-destination-backup-v1"

    migration_home="$migration_root/fresh-copy"
    mkdir -p "$migration_home/.pi/agent/sessions"
    printf '%s' auth > "$migration_home/.pi/agent/auth.json"
    printf '%s' session > "$migration_home/.pi/agent/sessions/current.jsonl"
    printf '%s' managed > "$migration_home/.pi/agent/models.json"
    migration_source_before="$(python3 -I "$digest_script" "$migration_home/.pi/agent")"
    HOME="$migration_home" ${task9PiProfileMigrationScript}
    test "$(cat "$migration_home/.config/pi/auth.json")" = auth
    test "$(cat "$migration_home/.config/pi/sessions/current.jsonl")" = session
    test "$(cat "$migration_home/.config/pi/models.json")" = managed
    test -f "$migration_home/.config/.nix-pi-profile-migrated-v1"
    migration_source_after="$(python3 -I "$digest_script" "$migration_home/.pi/agent")"
    test "$migration_source_before" = "$migration_source_after"

    migration_home="$migration_root/no-overwrite"
    mkdir -p \
      "$migration_home/.pi/agent/sessions" \
      "$migration_home/.config/pi/sessions"
    chmod 0750 "$migration_home/.config/pi"
    chmod 0700 "$migration_home/.pi/agent/sessions"
    chmod 0751 "$migration_home/.config/pi/sessions"
    printf '%s' old > "$migration_home/.pi/agent/settings.json"
    printf '%s' copied > "$migration_home/.pi/agent/sessions/copied.jsonl"
    printf '%s' new > "$migration_home/.config/pi/settings.json"
    HOME="$migration_home" ${task9PiProfileMigrationScript}
    test "$(cat "$migration_home/.config/pi/settings.json")" = new
    test "$(cat "$migration_home/.config/pi/sessions/copied.jsonl")" = copied
    test "$(stat -c %a "$migration_home/.config/pi")" = 750
    test "$(stat -c %a "$migration_home/.config/pi/sessions")" = 751
    printf '%s' later > "$migration_home/.pi/agent/created-after-migration"
    HOME="$migration_home" ${task9PiProfileMigrationScript}
    test ! -e "$migration_home/.config/pi/created-after-migration"

    migration_home="$migration_root/legacy-parent-alias"
    migration_legacy_root="$migration_root/legacy-parent-target"
    mkdir -p "$migration_home" "$migration_legacy_root/agent"
    ln -s "$migration_legacy_root" "$migration_home/.pi"
    printf '%s' aliased > "$migration_legacy_root/agent/auth.json"
    HOME="$migration_home" ${task9PiProfileMigrationScript}
    test "$(cat "$migration_home/.config/pi/auth.json")" = aliased
    test "$(cat "$migration_legacy_root/agent/auth.json")" = aliased

    migration_home="$migration_root/same-target"
    mkdir -p "$migration_home/.pi" "$migration_home/.config/pi"
    printf '%s' present > "$migration_home/.config/pi/auth.json"
    ln -s "$migration_home/.config/pi" "$migration_home/.pi/agent"
    HOME="$migration_home" ${task9PiProfileMigrationScript}
    test "$(cat "$migration_home/.config/pi/auth.json")" = present
    test -f "$migration_home/.config/.nix-pi-profile-migrated-v1"

    migration_home="$migration_root/live-inverse-link"
    mkdir -p \
      "$migration_home/.config" \
      "$migration_home/.pi/agent/extensions/nix-gallery" \
      "$migration_home/.pi/agent/sessions" \
      "$migration_home/.pi/destination-only"
    chmod 0755 "$migration_home/.pi"
    chmod 0751 "$migration_home/.pi/destination-only"
    ln -s ../.pi "$migration_home/.config/pi"
    printf '%s' destination > "$migration_home/.pi/auth.json"
    printf '%s' destination-only > "$migration_home/.pi/destination-only/value"
    printf '%s' source > "$migration_home/.pi/agent/auth.json"
    printf '%s' session > "$migration_home/.pi/agent/sessions/current.jsonl"
    printf '%s' old > "$migration_home/.pi/agent/a"
    ln "$migration_home/.pi/agent/a" "$migration_home/.pi/agent/b"
    ln -s /nix/store/generated-gallery \
      "$migration_home/.pi/agent/extensions/nix-gallery/index.ts"
    printf '%s' user-state > "$migration_home/.pi/agent/.nix-pi-profile-stage-ready-v1"
    printf '%s' new > "$migration_home/.pi/a"
    migration_legacy_before="$(python3 -I "$digest_script" "$migration_home/.pi")"
    HOME="$migration_home" ${task9PiProfileMigrationScript}
    test ! -L "$migration_home/.config/pi"
    test -d "$migration_home/.config/pi"
    test ! -e "$migration_home/.config/.pi-profile-destination-backup-v1"
    test "$(cat "$migration_home/.config/pi/auth.json")" = destination
    test "$(cat "$migration_home/.config/pi/sessions/current.jsonl")" = session
    test "$(cat "$migration_home/.config/pi/destination-only/value")" = destination-only
    test "$(cat "$migration_home/.config/pi/a")" = new
    test "$(cat "$migration_home/.config/pi/b")" = old
    test "$(cat "$migration_home/.config/pi/.nix-pi-profile-stage-ready-v1")" = user-state
    test "$(cat "$migration_home/.pi/agent/.nix-pi-profile-stage-ready-v1")" = user-state
    test ! "$migration_home/.config/pi/a" -ef "$migration_home/.config/pi/b"
    test ! -e "$migration_home/.config/pi/agent/agent"
    test "$(readlink "$migration_home/.config/pi/agent/extensions/nix-gallery/index.ts")" = \
      /nix/store/generated-gallery
    test "$(stat -c %a "$migration_home/.config/pi")" = 700
    test "$(stat -c %a "$migration_home/.config/pi/destination-only")" = 751
    test "$(stat -c %a "$migration_home/.pi")" = 755
    test -f "$migration_home/.config/.nix-pi-profile-migrated-v1"
    migration_legacy_after="$(python3 -I "$digest_script" "$migration_home/.pi")"
    test "$migration_legacy_before" = "$migration_legacy_after"

    migration_home="$migration_root/interrupted-ready-stage"
    migration_stage="$migration_home/.config/.pi-profile-migration.crash"
    mkdir -p \
      "$migration_home/.config" \
      "$migration_home/.pi/agent" \
      "$migration_stage/sessions"
    printf '%s' legacy > "$migration_home/.pi/agent/auth.json"
    printf '%s' staged > "$migration_stage/auth.json"
    printf '%s' staged-session > "$migration_stage/sessions/current.jsonl"
    chmod 0700 "$migration_stage"
    touch "$migration_stage.ready"
    ln -s ../.pi "$migration_home/.config/.pi-profile-destination-backup-v1"
    HOME="$migration_home" ${task9PiProfileMigrationScript}
    test ! -L "$migration_home/.config/pi"
    test "$(cat "$migration_home/.config/pi/auth.json")" = staged
    test "$(cat "$migration_home/.config/pi/sessions/current.jsonl")" = staged-session
    test "$(stat -c %a "$migration_home/.config/pi")" = 700
    test ! -e "$migration_home/.config/.pi-profile-destination-backup-v1"
    test ! -e "$migration_stage.ready"
    test -f "$migration_home/.config/.nix-pi-profile-migrated-v1"

    migration_home="$migration_root/interrupted-incomplete-stage"
    migration_stage="$migration_home/.config/.pi-profile-migration.crash"
    mkdir -p "$migration_home/.config" "$migration_home/.pi/agent" "$migration_stage"
    ln -s ../.pi "$migration_home/.config/.pi-profile-destination-backup-v1"
    set +e
    HOME="$migration_home" ${task9PiProfileMigrationScript} \
      >"$migration_root/interrupted-incomplete-stage.output" 2>&1
    migration_status=$?
    set -e
    test "$migration_status" -ne 0
    test -L "$migration_home/.config/pi"
    test ! -e "$migration_home/.config/.pi-profile-destination-backup-v1"
    grep -F "restored the destination after an incomplete migration" \
      "$migration_root/interrupted-incomplete-stage.output" >/dev/null

    migration_home="$migration_root/interrupted-real-destination"
    migration_stage="$migration_home/.config/.pi-profile-migration.crash"
    migration_backup="$migration_home/.config/.pi-profile-destination-backup-v1"
    mkdir -p \
      "$migration_home/.config" \
      "$migration_home/.pi/agent" \
      "$migration_stage/sessions" \
      "$migration_backup"
    chmod 0750 "$migration_stage" "$migration_backup"
    printf '%s' legacy > "$migration_home/.pi/agent/settings.json"
    printf '%s' destination > "$migration_backup/settings.json"
    printf '%s' destination > "$migration_stage/settings.json"
    printf '%s' staged > "$migration_stage/sessions/current.jsonl"
    touch "$migration_stage.ready"
    HOME="$migration_home" ${task9PiProfileMigrationScript}
    test "$(cat "$migration_home/.config/pi/settings.json")" = destination
    test "$(cat "$migration_home/.config/pi/sessions/current.jsonl")" = staged
    test "$(stat -c %a "$migration_home/.config/pi")" = 750
    test ! -e "$migration_backup"
    test ! -e "$migration_stage.ready"
    test -f "$migration_home/.config/.nix-pi-profile-migrated-v1"

    migration_home="$migration_root/interrupted-post-swap-with-backup"
    migration_ready="$migration_home/.config/.pi-profile-migration.crash.ready"
    migration_backup="$migration_home/.config/.pi-profile-destination-backup-v1"
    mkdir -p \
      "$migration_home/.config/pi/sessions" \
      "$migration_home/.pi/agent" \
      "$migration_backup"
    chmod 0750 "$migration_home/.config/pi"
    printf '%s' installed > "$migration_home/.config/pi/settings.json"
    printf '%s' installed-session > "$migration_home/.config/pi/sessions/current.jsonl"
    printf '%s' previous > "$migration_backup/settings.json"
    touch "$migration_ready"
    HOME="$migration_home" ${task9PiProfileMigrationScript}
    test "$(cat "$migration_home/.config/pi/settings.json")" = installed
    test "$(cat "$migration_home/.config/pi/sessions/current.jsonl")" = installed-session
    test "$(stat -c %a "$migration_home/.config/pi")" = 750
    test ! -e "$migration_backup"
    test ! -e "$migration_ready"
    test -f "$migration_home/.config/.nix-pi-profile-migrated-v1"

    migration_home="$migration_root/interrupted-post-swap-without-backup"
    migration_ready="$migration_home/.config/.pi-profile-migration.crash.ready"
    mkdir -p "$migration_home/.config/pi" "$migration_home/.pi/agent"
    printf '%s' installed > "$migration_home/.config/pi/auth.json"
    touch "$migration_ready"
    HOME="$migration_home" ${task9PiProfileMigrationScript}
    test "$(cat "$migration_home/.config/pi/auth.json")" = installed
    test ! -e "$migration_ready"
    test -f "$migration_home/.config/.nix-pi-profile-migrated-v1"

    migration_home="$migration_root/interrupted-post-marker-backup"
    migration_backup="$migration_home/.config/.pi-profile-destination-backup-v1"
    mkdir -p "$migration_home/.config/pi" "$migration_home/.pi/agent" "$migration_backup"
    printf '%s' installed > "$migration_home/.config/pi/auth.json"
    printf '%s' previous > "$migration_backup/auth.json"
    touch "$migration_home/.config/.nix-pi-profile-migrated-v1"
    HOME="$migration_home" ${task9PiProfileMigrationScript}
    test "$(cat "$migration_home/.config/pi/auth.json")" = installed
    test ! -e "$migration_backup"

    migration_home="$migration_root/interrupted-absent-destination"
    migration_stage="$migration_home/.config/.pi-profile-migration.crash"
    mkdir -p "$migration_home/.config" "$migration_home/.pi/agent" "$migration_stage"
    chmod 0700 "$migration_stage"
    printf '%s' legacy > "$migration_home/.pi/agent/auth.json"
    printf '%s' staged > "$migration_stage/auth.json"
    touch "$migration_stage.ready"
    HOME="$migration_home" ${task9PiProfileMigrationScript}
    test "$(cat "$migration_home/.config/pi/auth.json")" = staged
    test "$(stat -c %a "$migration_home/.config/pi")" = 700
    test ! -e "$migration_stage.ready"
    test -f "$migration_home/.config/.nix-pi-profile-migrated-v1"

    migration_home="$migration_root/interrupted-symlink-stage"
    migration_stage_target="$migration_home/stage-target"
    mkdir -p "$migration_home/.config" "$migration_home/.pi/agent" "$migration_stage_target"
    ln -s "$migration_stage_target" "$migration_home/.config/.pi-profile-migration.crash"
    set +e
    HOME="$migration_home" ${task9PiProfileMigrationScript} \
      >"$migration_root/interrupted-symlink-stage.output" 2>&1
    migration_status=$?
    set -e
    test "$migration_status" -ne 0
    grep -F "staging path is a symlink" \
      "$migration_root/interrupted-symlink-stage.output" >/dev/null

    migration_home="$migration_root/invalid-source"
    mkdir -p "$migration_home/.pi"
    printf '%s' invalid > "$migration_home/.pi/agent"
    set +e
    HOME="$migration_home" ${task9PiProfileMigrationScript} \
      >"$migration_root/invalid-source.output" 2>&1
    migration_status=$?
    set -e
    test "$migration_status" -ne 0
    grep -F "source is not a directory" "$migration_root/invalid-source.output" >/dev/null
    test ! -e "$migration_home/.config/.nix-pi-profile-migrated-v1"

    migration_home="$migration_root/invalid-destination"
    mkdir -p "$migration_home/.pi/agent" "$migration_home/.config"
    printf '%s' invalid > "$migration_home/.config/pi"
    set +e
    HOME="$migration_home" ${task9PiProfileMigrationScript} \
      >"$migration_root/invalid-destination.output" 2>&1
    migration_status=$?
    set -e
    test "$migration_status" -ne 0
    grep -F "destination is not a directory" \
      "$migration_root/invalid-destination.output" >/dev/null

    migration_home="$migration_root/production-agent-root"
    mkdir -p \
      "$migration_home/.pi/agent/sessions" \
      "$migration_home/.config/pi/agent/sessions"
    printf '%s' legacy > "$migration_home/.pi/agent/auth.json"
    printf '%s' late > "$migration_home/.pi/agent/sessions/late.jsonl"
    printf '%s' destination > "$migration_home/.config/pi/agent/auth.json"
    migration_source_before="$(python3 -I "$digest_script" "$migration_home/.pi/agent")"
    HOME="$migration_home" ${task9PiAgentProfileMigrationScript}
    test "$(cat "$migration_home/.config/pi/agent/auth.json")" = destination
    test "$(cat "$migration_home/.config/pi/agent/sessions/late.jsonl")" = late
    test -f "$migration_home/.config/pi/.nix-pi-profile-migrated-v1"
    migration_source_after="$(python3 -I "$digest_script" "$migration_home/.pi/agent")"
    test "$migration_source_before" = "$migration_source_after"

    migration_home="$migration_root/production-agent-identity"
    mkdir -p "$migration_home/.config/pi/agent"
    printf '%s' shared > "$migration_home/.config/pi/agent/auth.json"
    ln -s "$migration_home/.config/pi" "$migration_home/.pi"
    migration_identity_inode="$(stat -c %i "$migration_home/.config/pi/agent")"
    migration_identity_before="$(python3 -I "$digest_script" \
      "$migration_home/.config/pi/agent")"
    HOME="$migration_home" ${task9PiAgentProfileMigrationScript}
    test -f "$migration_home/.config/pi/.nix-pi-profile-migrated-v1"
    test "$(stat -c %i "$migration_home/.config/pi/agent")" = "$migration_identity_inode"
    migration_identity_after="$(python3 -I "$digest_script" \
      "$migration_home/.config/pi/agent")"
    test "$migration_identity_before" = "$migration_identity_after"

    migration_home="$migration_root/production-agent-inverse-parent"
    mkdir -p "$migration_home/.config" "$migration_home/.pi/agent"
    printf '%s' source > "$migration_home/.pi/agent/auth.json"
    ln -s ../.pi "$migration_home/.config/pi"
    migration_inverse_before="$(python3 -I "$digest_script" "$migration_home")"
    set +e
    HOME="$migration_home" ${task9PiAgentProfileMigrationScript} \
      >"$migration_root/production-agent-inverse-parent.output" 2>&1
    migration_status=$?
    set -e
    test "$migration_status" -ne 0
    grep -F "destination parent is a symlink" \
      "$migration_root/production-agent-inverse-parent.output" >/dev/null
    migration_inverse_after="$(python3 -I "$digest_script" "$migration_home")"
    test "$migration_inverse_before" = "$migration_inverse_after"

    migration_home="$migration_root/legacy-root-finalizer"
    mkdir -p "$migration_home/.config/pi/agent" "$migration_home/.pi/agent" "$migration_home/.pi/rules"
    printf '%s' active > "$migration_home/.config/pi/agent/auth.json"
    printf '%s' legacy > "$migration_home/.pi/agent/auth.json"
    printf '%s' rule > "$migration_home/.pi/rules/local.md"
    ln "$migration_home/.pi/rules/local.md" "$migration_home/.pi/rules/linked.md"
    migration_legacy_before="$(python3 -I "$digest_script" "$migration_home/.pi")"
    HOME="$migration_home" ${task9PiLegacyRootScript}
    test -L "$migration_home/.pi"
    test "$(readlink -f "$migration_home/.pi")" = \
      "$(readlink -f "$migration_home/.config/pi")"
    test -d "$migration_home/.pi-legacy-v1"
    migration_legacy_after="$(python3 -I "$digest_script" \
      "$migration_home/.pi-legacy-v1")"
    test "$migration_legacy_before" = "$migration_legacy_after"
    test "$migration_home/.pi-legacy-v1/rules/local.md" -ef \
      "$migration_home/.pi-legacy-v1/rules/linked.md"
    HOME="$migration_home" ${task9PiLegacyRootScript}
    test -L "$migration_home/.pi"
    test -d "$migration_home/.pi-legacy-v1"

    migration_home="$migration_root/legacy-root-fresh-home"
    mkdir -p "$migration_home"
    HOME="$migration_home" ${task9PiLegacyRootScript}
    test -d "$migration_home/.config/pi"
    test "$(stat -c %a "$migration_home/.config/pi")" = 700
    test -L "$migration_home/.pi"
    test "$(readlink -f "$migration_home/.pi")" = \
      "$(readlink -f "$migration_home/.config/pi")"

    migration_home="$migration_root/legacy-root-dry-run"
    mkdir -p "$migration_home/.config/pi/agent" "$migration_home/.pi/agent"
    DRY_RUN=1 HOME="$migration_home" ${task9PiLegacyRootScript}
    test -d "$migration_home/.pi"
    test ! -L "$migration_home/.pi"
    test ! -e "$migration_home/.pi-legacy-v1"

    migration_home="$migration_root/legacy-root-conflict"
    mkdir -p \
      "$migration_home/.config/pi" \
      "$migration_home/.pi" \
      "$migration_home/.pi-legacy-v1"
    set +e
    HOME="$migration_home" ${task9PiLegacyRootScript} \
      >"$migration_root/legacy-root-conflict.output" 2>&1
    migration_status=$?
    set -e
    test "$migration_status" -ne 0
    grep -F "legacy root and backup both exist" \
      "$migration_root/legacy-root-conflict.output" >/dev/null
    test -d "$migration_home/.pi"
    test -d "$migration_home/.pi-legacy-v1"

    migration_home="$migration_root/legacy-root-wrong-link"
    mkdir -p "$migration_home/.config/pi" "$migration_home/wrong"
    ln -s "$migration_home/wrong" "$migration_home/.pi"
    set +e
    HOME="$migration_home" ${task9PiLegacyRootScript} \
      >"$migration_root/legacy-root-wrong-link.output" 2>&1
    migration_status=$?
    set -e
    test "$migration_status" -ne 0
    grep -F "legacy root symlink has an unexpected target" \
      "$migration_root/legacy-root-wrong-link.output" >/dev/null
    test ! -e "$migration_home/.pi-legacy-v1"

    migration_home="$migration_root/legacy-root-interrupted-after-move"
    mkdir -p "$migration_home/.config/pi/agent" "$migration_home/.pi-legacy-v1/rules"
    printf '%s' backup > "$migration_home/.pi-legacy-v1/rules/local.md"
    migration_legacy_before="$(python3 -I "$digest_script" \
      "$migration_home/.pi-legacy-v1")"
    HOME="$migration_home" ${task9PiLegacyRootScript}
    test -L "$migration_home/.pi"
    migration_legacy_after="$(python3 -I "$digest_script" \
      "$migration_home/.pi-legacy-v1")"
    test "$migration_legacy_before" = "$migration_legacy_after"

    migration_home="$migration_root/legacy-root-missing-destination-with-backup"
    mkdir -p "$migration_home/.pi-legacy-v1"
    set +e
    HOME="$migration_home" ${task9PiLegacyRootScript} \
      >"$migration_root/legacy-root-missing-destination-with-backup.output" 2>&1
    migration_status=$?
    set -e
    test "$migration_status" -ne 0
    grep -F "destination is absent after profile migration" \
      "$migration_root/legacy-root-missing-destination-with-backup.output" >/dev/null

    retired_root="$TMPDIR/retired-mcp-cleanup"
    retired_home="$retired_root/home"
    mkdir -p \
      "$retired_home/.config/claude/personal" \
      "$retired_home/.config/claude/positron" \
      "$retired_home/.config/codex" \
      "$retired_home/.config/codex-explicit" \
      "$retired_home/.config/codex-inline" \
      "$retired_home/.config/codex-sole" \
      "$retired_home/.config/factory" \
      "$retired_home/.config/opencode" \
      "$retired_home/.config/pi/agent"

    cat >"$retired_home/.config/codex/config.toml" <<'EOF'
    model = "keep"
    note = """
    [mcp_servers.anvil]
    this is inert multiline text
    """

    [projects."/tmp/anvil"]
    trusted = true

    [mcp_servers.keep]
    command = "/bin/keep"

    [mcp_servers.anvil]
    command = "anvil-mcp"

    [mcp_servers.anvil.env]
    SYNTHETIC_SECRET = "must-not-print"
    EOF
    cp "$retired_home/.config/codex/config.toml" \
      "$retired_home/.config/codex/config.toml.bak"
    cat >"$retired_home/.config/codex-explicit/config.toml" <<'EOF'
    [mcp_servers]
    anvil = { command = "anvil-mcp" }
    EOF
    cat >"$retired_home/.config/codex-inline/config.toml" <<'EOF'
    mcp_servers = { anvil = { command = "anvil-mcp" } }
    EOF
    cat >"$retired_home/.config/codex-sole/config.toml" <<'EOF'
    [mcp_servers.anvil]
    command = "anvil-mcp"
    EOF

    cat >"$retired_home/.config/claude/personal/.claude.json" <<'EOF'
    {
      "mcpServers": {
        "anvil": {"command": "anvil-mcp"},
        "keep": {"command": "/bin/keep"}
      },
      "cachedGrowthBookFeatures": {"tengu_anvil_flag": true},
      "largeInteger": 9007199254740993,
      "preciseDecimal": 0.123456789012345678901234567890
    }
    EOF
    cp "$retired_home/.config/claude/personal/.claude.json" \
      "$retired_home/.config/claude/positron/.claude.json"

    cat >"$retired_home/.config/pi/agent/mcp-cache.json" <<'EOF'
    {
      "version": 1,
      "servers": {
        "anvil": {"tools": [{"name": "stale"}]},
        "keep": {"tools": [{"name": "keep"}]}
      }
    }
    EOF

    retired_manifest="$retired_root/manifest.json"
    cat >"$retired_manifest" <<'EOF'
    {
      "items": {
        "mcp_servers": {
          "anvil": {"source_hash": "old"},
          "anvil-tools": {"source_hash": "old"},
          "keep": {"source_hash": "keep"}
        },
        "skills": {
          "anvil": {"source_hash": "old"},
          "keep": {"source_hash": "keep"}
        }
      },
      "sentinel": "unchanged"
    }
    EOF
    for retired_manifest_root in \
      .config/claude/personal \
      .config/claude/positron \
      .config/codex \
      .config/factory \
      .config/opencode; do
      cp "$retired_manifest" \
        "$retired_home/$retired_manifest_root/.prompt-deploy-manifest.json"
    done

    chmod 0600 \
      "$retired_home/.config/codex/config.toml" \
      "$retired_home/.config/codex/config.toml.bak" \
      "$retired_home/.config/claude/personal/.claude.json" \
      "$retired_home/.config/claude/positron/.claude.json"
    chmod 0640 "$retired_home/.config/pi/agent/mcp-cache.json"
    retired_expect_xattr=0
    if command -v xattr >/dev/null 2>&1; then
      xattr -w com.openai.synthetic preserved \
        "$retired_home/.config/codex/config.toml"
      retired_expect_xattr=1
    fi

    retired_program=${retiredMcpCleanup.program}/bin/nix-managed-retired-mcp-cleanup
    retired_plan=${lib.escapeShellArg retiredMcpCleanup.planJson}
    "$retired_program" --home "$retired_home" --plan-json "$retired_plan"

    for retired_toml in \
      "$retired_home/.config/codex/config.toml" \
      "$retired_home/.config/codex/config.toml.bak"; do
      tomlq -e '.mcp_servers.anvil == null' "$retired_toml" >/dev/null
      tomlq -e '.mcp_servers.keep.command == "/bin/keep"' "$retired_toml" >/dev/null
      tomlq -e '.projects."/tmp/anvil".trusted == true' "$retired_toml" >/dev/null
      tomlq -e '.note | contains("[mcp_servers.anvil]")' "$retired_toml" >/dev/null
      test "$(stat -c %a "$retired_toml")" = 600
    done
    if [ "$retired_expect_xattr" -eq 1 ]; then
      test "$(xattr -p com.openai.synthetic \
        "$retired_home/.config/codex/config.toml")" = preserved
    fi
    for retired_toml in \
      "$retired_home/.config/codex-explicit/config.toml" \
      "$retired_home/.config/codex-inline/config.toml" \
      "$retired_home/.config/codex-sole/config.toml"; do
      tomlq -e '(.mcp_servers // {}) | has("anvil") | not' "$retired_toml" >/dev/null
    done
    for retired_claude in \
      "$retired_home/.config/claude/personal/.claude.json" \
      "$retired_home/.config/claude/positron/.claude.json"; do
      jq -e '.mcpServers.anvil == null' "$retired_claude" >/dev/null
      jq -e '.mcpServers.keep.command == "/bin/keep"' "$retired_claude" >/dev/null
      jq -e '.cachedGrowthBookFeatures.tengu_anvil_flag == true' "$retired_claude" >/dev/null
      python3 -c \
        'import json,sys; assert json.load(open(sys.argv[1]))["largeInteger"] == 9007199254740993' \
        "$retired_claude"
      grep -F '0.123456789012345678901234567890' "$retired_claude" >/dev/null
      test "$(stat -c %a "$retired_claude")" = 600
    done
    jq -e '.servers.anvil == null and .servers.keep.tools[0].name == "keep"' \
      "$retired_home/.config/pi/agent/mcp-cache.json" >/dev/null
    test "$(stat -c %a "$retired_home/.config/pi/agent/mcp-cache.json")" = 640
    for retired_manifest_root in \
      .config/claude/personal \
      .config/claude/positron \
      .config/codex \
      .config/factory \
      .config/opencode; do
      retired_deployed_manifest="$retired_home/$retired_manifest_root/.prompt-deploy-manifest.json"
      jq -e '
        .items.mcp_servers.anvil == null
        and .items.mcp_servers."anvil-tools" == null
        and .items.mcp_servers.keep.source_hash == "keep"
        and .items.skills.anvil == null
        and .items.skills.keep.source_hash == "keep"
        and .sentinel == "unchanged"
      ' "$retired_deployed_manifest" >/dev/null
    done
    test -z "$(find "$retired_home" -name '.retired-mcp.*' -print -quit)"

    retired_digest_before="$(python3 -I "$digest_script" "$retired_home")"
    retired_inode_before="$(stat -c %i "$retired_home/.config/codex/config.toml")"
    "$retired_program" --home "$retired_home" --plan-json "$retired_plan"
    retired_digest_after="$(python3 -I "$digest_script" "$retired_home")"
    test "$retired_digest_before" = "$retired_digest_after"
    test "$retired_inode_before" = \
      "$(stat -c %i "$retired_home/.config/codex/config.toml")"

    retired_dry_home="$retired_root/dry-home"
    mkdir -p "$retired_dry_home/.config/codex"
    cp "$retired_home/.config/codex/config.toml.bak" \
      "$retired_dry_home/.config/codex/config.toml"
    cat >>"$retired_dry_home/.config/codex/config.toml" <<'EOF'

    [mcp_servers.anvil]
    command = "anvil-mcp"
    EOF
    retired_dry_before="$(sha256sum "$retired_dry_home/.config/codex/config.toml")"
    "$retired_program" --dry-run --home "$retired_dry_home" --plan-json "$retired_plan"
    test "$retired_dry_before" = \
      "$(sha256sum "$retired_dry_home/.config/codex/config.toml")"

    retired_bad_home="$retired_root/bad-home"
    mkdir -p "$retired_bad_home/.config/pi/agent"
    printf '%s' '{"servers":{"anvil":{},"anvil":{}},"secret":"DO_NOT_PRINT"}' \
      >"$retired_bad_home/.config/pi/agent/mcp-cache.json"
    set +e
    "$retired_program" --home "$retired_bad_home" --plan-json "$retired_plan" \
      >"$retired_root/bad.output" 2>&1
    retired_status=$?
    set -e
    test "$retired_status" -ne 0
    grep -F "duplicate JSON key" "$retired_root/bad.output" >/dev/null
    test "$(grep -F -c DO_NOT_PRINT "$retired_root/bad.output")" = 0

    retired_type_home="$retired_root/type-home"
    mkdir -p "$retired_type_home/.config/claude/personal"
    printf '%s' '{"mcpServers":[],"secret":"DO_NOT_PRINT"}' \
      >"$retired_type_home/.config/claude/personal/.claude.json"
    set +e
    "$retired_program" --home "$retired_type_home" --plan-json "$retired_plan" \
      >"$retired_root/type.output" 2>&1
    retired_status=$?
    set -e
    test "$retired_status" -ne 0
    grep -F "managed JSON container has the wrong type" \
      "$retired_root/type.output" >/dev/null
    test "$(grep -F -c DO_NOT_PRINT "$retired_root/type.output")" = 0

    retired_null_home="$retired_root/null-home"
    mkdir -p "$retired_null_home/.config/claude/personal"
    printf '%s' '{"mcpServers":null,"secret":"DO_NOT_PRINT"}' \
      >"$retired_null_home/.config/claude/personal/.claude.json"
    set +e
    "$retired_program" --home "$retired_null_home" --plan-json "$retired_plan" \
      >"$retired_root/null.output" 2>&1
    retired_status=$?
    set -e
    test "$retired_status" -ne 0
    grep -F "managed JSON container has the wrong type" \
      "$retired_root/null.output" >/dev/null
    test "$(grep -F -c DO_NOT_PRINT "$retired_root/null.output")" = 0

    retired_nan_home="$retired_root/nan-home"
    mkdir -p "$retired_nan_home/.config/pi/agent"
    printf '%s' '{"servers":{"anvil":{}},"value":NaN,"secret":"DO_NOT_PRINT"}' \
      >"$retired_nan_home/.config/pi/agent/mcp-cache.json"
    set +e
    "$retired_program" --home "$retired_nan_home" --plan-json "$retired_plan" \
      >"$retired_root/nan.output" 2>&1
    retired_status=$?
    set -e
    test "$retired_status" -ne 0
    grep -F "non-standard JSON constant" "$retired_root/nan.output" >/dev/null
    test "$(grep -F -c DO_NOT_PRINT "$retired_root/nan.output")" = 0

    retired_symlink_home="$retired_root/symlink-home"
    mkdir -p "$retired_symlink_home/.config/codex" "$retired_root/outside"
    printf '%s' '[mcp_servers.anvil]' >"$retired_root/outside/config.toml"
    ln -s "$retired_root/outside/config.toml" \
      "$retired_symlink_home/.config/codex/config.toml"
    set +e
    "$retired_program" --home "$retired_symlink_home" --plan-json "$retired_plan" \
      >"$retired_root/symlink.output" 2>&1
    retired_status=$?
    set -e
    test "$retired_status" -ne 0
    grep -F "refusing unsafe mutable config path" \
      "$retired_root/symlink.output" >/dev/null
    grep -F '[mcp_servers.anvil]' "$retired_root/outside/config.toml" >/dev/null

    retired_fifo_home="$retired_root/fifo-home"
    mkdir -p "$retired_fifo_home/.config/codex"
    mkfifo "$retired_fifo_home/.config/codex/config.toml"
    set +e
    timeout 5 "$retired_program" --home "$retired_fifo_home" --plan-json "$retired_plan" \
      >"$retired_root/fifo.output" 2>&1
    retired_status=$?
    set -e
    test "$retired_status" -ne 0
    test "$retired_status" -ne 124
    grep -F "refusing non-regular or shared mutable config" \
      "$retired_root/fifo.output" >/dev/null

    touch "$out"
  ''
