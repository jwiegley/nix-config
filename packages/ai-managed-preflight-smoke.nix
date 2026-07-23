{
  pkgs,
  src,
  homeManagerLib,
}:

let
  inherit (pkgs) lib;

  preflightFactory = import "${src}/config/ai/preflight.nix" {
    lib = lib // {
      inherit (homeManagerLib) hm;
    };
    inherit pkgs;
  };
  task9PreflightWithPi = preflightFactory {
    newPaths = [
      ".config/claude/personal/agents/new.md"
      ".config/claude/personal/agents/retained.md"
    ];
    piGuard = {
      path = ".pi/agent/mcp.json";
      forbiddenKeys = [
        "mcpServers"
        "imports"
      ];
    };
  };
  task9PreflightWithoutPi = preflightFactory {
    newPaths = [
      ".config/claude/personal/agents/new.md"
      ".config/claude/personal/agents/retained.md"
    ];
  };
  task9PiLeafPreflight = preflightFactory {
    newPaths = [ ".pi/agent/agents/bash-reviewer.md" ];
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
      ".pi/agent/agents/nix-managed.md"
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
  task9SharedLeafPreflightScript = writePreflightScript "task9-ai-shared-leaf-preflight" task9SharedLeafPreflight;
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
assert task9PreflightWithPi.activation.before == [ "checkLinkTargets" ];
assert task9PreflightWithPi.activation.after == [ ];
assert lib.hasInfix ".pi/agent/mcp.json" task9PreflightWithPi.script;
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

pkgs.runCommand "ai-managed-preflight-smoke"
  {
    nativeBuildInputs = [
      pkgs.coreutils
      pkgs.findutils
      pkgs.jq
      pkgs.python3
    ];
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
    pi_leaf_path=".pi/agent/agents/bash-reviewer.md"
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
      mkdir -p "$old_gen" "$old_files" "$pi_root/agent"
      ln -s "$old_files" "$old_gen/home-files"
      ln -s "$pi_root" "$old_files/.pi"
      ln -s "$old_files/.pi" "$case_home/.pi"
      make_leaf "$pi_root" "agent/unmanaged-sibling.json" '{"kept":true}'
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
        *task9-ai-pi-leaf-preflight)
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
          shared-pi-leaf-collision)
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
    make_leaf "$case_home" ".pi/agent/mcp.json" '{"imports":[]}'
    aggregate_output="$new_path: blocking leaf is a regular file: $case_home/$new_path
    .pi/agent/mcp.json: keep valid adapter JSON without top-level mcpServers or imports"
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
      ".pi/agent/agents/user-owned.md"
    do
      make_leaf "$case_home" "$sibling" user-owned
    done
    run_checked pass shared-agent-directories "" "${task9SharedLeafPreflightScript}" absent

    setup_empty_case shared-pi-real-directory
    make_leaf "$case_home" ".pi/agent/unmanaged-sibling.json" '{"kept":true}'
    run_checked pass shared-pi-real-directory "" "${task9PiLeafPreflightScript}" absent

    setup_pi_alias_case shared-pi-previous-alias
    run_checked pass shared-pi-previous-alias "" "${task9PiLeafPreflightScript}" present

    setup_pi_alias_case shared-pi-leaf-collision
    make_leaf "$pi_root" "agent/agents/bash-reviewer.md" unmanaged
    run_checked fail shared-pi-leaf-collision "$pi_leaf_path" \
      "${task9PiLeafPreflightScript}" present

    write_pi() {
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

    setup_empty_case pi-benign-symlink
    make_leaf "$case_root" pi-settings '{}'
    mkdir -p "$case_home/.pi/agent"
    ln -s "$case_root/pi-settings" "$case_home/.pi/agent/mcp.json"
    run_checked pass pi-benign-symlink "" "${task9PreflightScript}" absent

    setup_empty_case pi-mcp-servers
    write_pi '{"mcpServers":null}'
    run_checked fail pi-mcp-servers ".pi/agent/mcp.json" "${task9PreflightScript}" absent

    setup_empty_case pi-imports
    write_pi '{"imports":[]}'
    run_checked fail pi-imports ".pi/agent/mcp.json" "${task9PreflightScript}" absent

    setup_empty_case pi-malformed
    write_pi '{SECRET_SENTINEL'
    run_checked fail pi-malformed ".pi/agent/mcp.json" "${task9PreflightScript}" absent

    setup_empty_case pi-fifo
    mkdir -p "$case_home/.pi/agent"
    mkfifo "$case_home/.pi/agent/mcp.json"
    run_checked fail pi-fifo ".pi/agent/mcp.json"       "${task9PreflightBoundedScript}" absent

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
      run_checked fail "pi-$pi_case" ".pi/agent/mcp.json" \
        "${task9PreflightScript}" absent
    done

    setup_empty_case non-pi-ignores-adapter
    write_pi '{"mcpServers":null}'
    run_checked pass non-pi-ignores-adapter "" "${task9PreflightNoPiScript}" absent


    touch "$out"
  ''
