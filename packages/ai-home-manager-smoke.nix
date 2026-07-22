{ pkgs, src }:

pkgs.runCommand "ai-home-manager-smoke"
  {
    nativeBuildInputs = [ pkgs.python3 ];
  }
  ''
    python3 -I - "${src}/config/ai" <<'PY'
    import hashlib
    import os
    import re
    import stat
    import sys
    from pathlib import Path

    root = Path(sys.argv[1])

    agents = set(
        """
        bash-reviewer coq-reviewer cpp-pro cpp-reviewer elisp-reviewer
        emacs-lisp-pro fess-auditor haskell-pro haskell-reviewer nix-pro
        nix-reviewer perf-reviewer persian-translator prd-architect
        prompt-engineer python-pro python-reviewer rocq-pro rust-pro
        rust-reviewer security-reviewer sql-pro task-breakdown typescript-pro
        typescript-reviewer web-searcher
        """.split()
    )
    commands = set(
        """
        assess bankruptcy breakdown bugbot bugbot-stack capture cleanup
        code-review commit deep-review discover-bundles eliminate-dead-code
        expense-report fess fix fix-alert fix-ci fix-github-issue
        fix-integration fix-transcript flaky-rust forge gravity halt heavy
        infer-tasks initialize install-service journal lefthook markdown medium
        meeting-notes narrative nix-rebuild partner-cleanup
        partner-collaborator partner-reviewer prepare-with process-checklist
        productize proofread push query-builder quick-review rebase
        rebase-and-fix recommit remove-service report resolve respond restack
        retest retest-categorical review-github-pr run-orchestrator sec-audit
        sitrep smooth teams transcribe-image tron-debug webfix wiggum
        """.split()
    )
    skills = set(
        """
        anvil caveman comment-audit eliminate-dead-code fix-all fix-transcript
        forge it-voice johnw nixos node-red parallelize persian retest
        skill-creator swiftui toolkit wiggum
        """.split()
    )

    assert len(agents) == 26
    assert len(commands) == 65
    assert len(skills) == 18

    missing = [
        category
        for category in ("agents", "commands", "skills", "prompts")
        if not (root / category).is_dir()
    ]
    statusline = root / "statusline-command.sh"
    if not statusline.is_file():
        missing.append("statusline")
    if missing:
        print("ai-home-manager-smoke: missing asset categories:", file=sys.stderr)
        for category in missing:
            print(f"  {category}", file=sys.stderr)
        raise SystemExit(1)

    errors = []
    if root.is_symlink():
        errors.append("config/ai must not be a symlink")

    paths = []
    for directory, directories, files in os.walk(root, followlinks=False):
        base = Path(directory)
        paths.extend(base / name for name in directories)
        paths.extend(base / name for name in files)

    resolved_root = root.resolve(strict=True)

    # Bind every nested asset path, type, executable bit, symlink target, and byte.
    records = []
    for path in paths:
        relative = path.relative_to(root).as_posix().encode()
        mode = path.lstat().st_mode
        if stat.S_ISDIR(mode):
            fields = (relative, b"d", b"-", b"", b"0", b"")
        elif stat.S_ISREG(mode):
            data = path.read_bytes()
            fields = (
                relative,
                b"f",
                b"x" if mode & 0o111 else b"-",
                b"",
                str(len(data)).encode(),
                hashlib.sha256(data).hexdigest().encode(),
            )
        elif stat.S_ISLNK(mode):
            target = os.fsencode(os.readlink(path))
            fields = (
                relative,
                b"l",
                b"-",
                target,
                str(len(target)).encode(),
                hashlib.sha256(target).hexdigest().encode(),
            )
        else:
            errors.append(f"unsupported file type: {path.relative_to(root)}")
            continue
        records.append((relative, b"\0".join(fields) + b"\0"))

    asset_digest = hashlib.sha256(
        b"".join(record for _, record in sorted(records))
    ).hexdigest()
    expected_asset_digest = (
        "422c4e45bc09b660118f3f3651f7fbce632ec07dbc678105c323ab5cb74e1768"
    )
    if asset_digest != expected_asset_digest:
        errors.append(
            f"config/ai recursive digest mismatch: {asset_digest} "
            f"!= {expected_asset_digest}"
        )

    for path in paths:
        if not path.is_symlink():
            continue
        try:
            target = path.resolve(strict=True)
            target.relative_to(resolved_root)
        except (OSError, RuntimeError, ValueError) as error:
            errors.append(f"dangling or escaping symlink: {path.relative_to(root)}: {error}")

    if errors:
        print("ai-home-manager-smoke: asset check failed:", file=sys.stderr)
        for error in errors:
            print(f"  {error}", file=sys.stderr)
        raise SystemExit(1)

    for path in paths:
        name = path.name.lower()
        if (
            name.startswith(".promptdeploy")
            or name.startswith(".env")
            or "manifest" in name
            or "receipt" in name
            or (name.endswith(".json") and "selector" in name)
        ):
            errors.append(f"forbidden committed artifact: {path.relative_to(root)}")

    expected = {
        "agents": {f"{name}.md" for name in agents},
        "commands": {f"{name}.md" for name in commands},
        "skills": skills,
        "prompts": {"emacs.md", "spanish.md"},
    }
    expected_root = set(expected) | {"statusline-command.sh"}
    actual_root = {entry.name for entry in root.iterdir()}
    if actual_root != expected_root:
        errors.append(
            "config/ai inventory mismatch: "
            f"missing={sorted(expected_root - actual_root)!r} "
            f"unexpected={sorted(actual_root - expected_root)!r}"
        )

    for category, wanted in expected.items():
        directory = root / category
        actual = {entry.name for entry in directory.iterdir()}
        if actual != wanted:
            errors.append(
                f"{category} inventory mismatch: "
                f"missing={sorted(wanted - actual)!r} "
                f"unexpected={sorted(actual - wanted)!r}"
            )

    for category in ("agents", "commands", "prompts"):
        for name in expected[category]:
            if not (root / category / name).is_file():
                errors.append(f"not a regular file: {category}/{name}")

    for name in skills:
        skill = root / "skills" / name
        if not skill.is_dir():
            errors.append(f"not a skill tree: skills/{name}")
        elif not (skill / "SKILL.md").is_file():
            errors.append(f"missing SKILL.md: skills/{name}")

    if not os.access(statusline, os.X_OK):
        errors.append("statusline-command.sh is not executable")

    deployment_field = re.compile(
        r"(?:^|[,{])\s*['\"]?(only|except|droid_deploy)['\"]?\s*:",
        re.MULTILINE,
    )
    for path in paths:
        if path.suffix.lower() != ".md" or not path.is_file():
            continue
        try:
            lines = path.read_text(encoding="utf-8").splitlines()
        except (OSError, UnicodeError) as error:
            errors.append(f"cannot read UTF-8 Markdown {path.relative_to(root)}: {error}")
            continue
        if not lines or lines[0].strip() != "---":
            continue
        try:
            end = next(
                index
                for index, line in enumerate(lines[1:], start=1)
                if line.strip() == "---"
            )
        except StopIteration:
            errors.append(f"unterminated frontmatter: {path.relative_to(root)}")
            continue
        match = deployment_field.search("\n".join(lines[1:end]))
        if match:
            errors.append(
                f"deployment field {match.group(1)!r}: {path.relative_to(root)}"
            )

    if errors:
        print("ai-home-manager-smoke: asset check failed:", file=sys.stderr)
        for error in errors:
            print(f"  {error}", file=sys.stderr)
        raise SystemExit(1)
    PY

    touch "$out"
  ''
