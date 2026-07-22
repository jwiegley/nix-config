# Nix-native Fractal Support Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Package Plasma Fractal and Plasma Wiki reproducibly in `ai-nix`, expose them through named and default flake outputs, and select them in the shared `nix` package configuration.

**Architecture:** A focused `ai-nix` overlay builds the two pure-Python applications from pinned wheels and wraps their shell-backed runtime dependencies. Stable store paths expose—but do not deploy—the bundled skills. A Nix smoke derivation initializes a real temporary Fractal without launching an agent, while `nix` consumes both packages through its existing optional-package mechanism.

**Tech Stack:** Nix flakes, Nixpkgs `buildPythonApplication`, Python 3.14, PyPI wheels, Bash lifecycle scripts, Git, tmux, SQLite, Home Manager evaluation.

## Global Constraints

- Pin `plasma-fractal` at 1.0.0 with `sha256-ROekeFUmslh7y2h/cOMv7d2CCAc8PGxiJ7zNvr7pDoA=`.
- Pin `plasma-wiki` at 1.1.0 with `sha256-kZ5f3RrBoxK6GXs5xm+Ug7LcyS91XCY0CHkdkKssZys=`.
- Support `aarch64-darwin`, `aarch64-linux`, and `x86_64-linux`.
- Use `pkgs.plasma-fractal`; do not override Nixpkgs' GNOME Matrix client at `pkgs.fractal`.
- Preserve complete wheel resources, including node seeds, scripts, schemas, TUI files, and skill trees.
- Expose skills at `${pkgs.plasma-fractal}/share/skills/fractal` and `${pkgs.plasma-wiki}/share/skills/wiki` without deploying them.
- Never invoke `fractal install`, `pip`, `pipx`, or `uv tool install` during build or activation.
- Do not write `~/.claude/skills`, `~/.agents/skills`, credentials, or Fractal project state outside test temporary directories.
- Do not install Grok Build or Oh My Pi and do not claim the installed `pi` executable is Fractal's `omp` backend.
- Do not add a service, daemon, launch agent, or systemd unit.
- Do not update either flake lock.
- Do not rebuild, switch, activate, or deploy a host configuration.
- Preserve unrelated work in both repositories.
- Do not create commits unless the user separately requests them.

---

## File Structure

### Create

- `/Users/johnw/src/ai-nix/overlays/30-fractal.nix` — the `plasma-wiki` and `plasma-fractal` derivations and their runtime wrappers.
- `/Users/johnw/src/ai-nix/overlays/tests/plasma-fractal-smoke.nix` — clean-environment package and local lifecycle smoke test.

### Modify

- `/Users/johnw/src/ai-nix/flake.nix` — register the overlay, smoke check, named packages, and default-toolchain packages.
- `/Users/johnw/src/ai-nix/scripts/test.sh` — assert the named outputs and exact versions.
- `/Users/johnw/src/ai-nix/README.md` — document Fractal, Wiki, supported installed backends, and deferred skill deployment.
- `/Users/johnw/src/nix/config/packages.nix` — select `plasma-wiki` and `plasma-fractal` through `optPkg`.

### Verify without modifying

- `/Users/johnw/src/ai-nix/flake.lock`
- `/Users/johnw/src/nix/flake.lock`
- `/Users/johnw/dl/fractal-nix-skills-management-handoff.md`

---

### Task 1: Add the failing Fractal lifecycle smoke check

**Files:**
- Create: `/Users/johnw/src/ai-nix/overlays/tests/plasma-fractal-smoke.nix`
- Modify: `/Users/johnw/src/ai-nix/flake.nix` in the `checks = forAllSystems` attribute set
- Test: `/Users/johnw/src/ai-nix/overlays/tests/plasma-fractal-smoke.nix`

**Interfaces:**
- Consumes: future top-level package attributes `pkgs.plasma-fractal` and `pkgs.plasma-wiki`.
- Produces: `checks.<system>.fractal-smoke`, a derivation that proves CLI, resource, wrapper, Git, Wiki, and node-initialization behavior.

- [ ] **Step 1: Confirm both repositories are clean apart from approved planning documents**

Run:

```bash
git -C /Users/johnw/src/ai-nix status --short --branch
git -C /Users/johnw/src/nix status --short --branch
```

Expected: `nix` is clean; `ai-nix` contains only the approved untracked `docs/` tree. Stop if any unrelated path appears.

- [ ] **Step 2: Write the smoke derivation before defining either package**

Create `/Users/johnw/src/ai-nix/overlays/tests/plasma-fractal-smoke.nix` with:

```nix
{
  coreutils,
  git,
  gnugrep,
  plasma-fractal,
  plasma-wiki,
  runCommand,
}:

runCommand "plasma-fractal-smoke"
  {
    nativeBuildInputs = [
      coreutils
      gnugrep
    ];
  }
  ''
    set -euo pipefail

    export HOME="$TMPDIR/home"
    export XDG_CACHE_HOME="$HOME/.cache"
    export XDG_CONFIG_HOME="$HOME/.config"
    export TMUX_TMPDIR="$TMPDIR/tmux"
    export COLUMNS=120
    mkdir -p "$HOME" "$XDG_CACHE_HOME" "$XDG_CONFIG_HOME" "$TMUX_TMPDIR"

    clean_path="${plasma-fractal}/bin:${plasma-wiki}/bin"
    run_fractal() {
      env -i \
        HOME="$HOME" \
        XDG_CACHE_HOME="$XDG_CACHE_HOME" \
        XDG_CONFIG_HOME="$XDG_CONFIG_HOME" \
        TMUX_TMPDIR="$TMUX_TMPDIR" \
        COLUMNS="$COLUMNS" \
        OFFLINE_MODE=true \
        PATH="$clean_path" \
        TERM=xterm-256color \
        ${plasma-fractal}/bin/fractal "$@"
    }
    run_wiki() {
      env -i \
        HOME="$HOME" \
        XDG_CACHE_HOME="$XDG_CACHE_HOME" \
        XDG_CONFIG_HOME="$XDG_CONFIG_HOME" \
        OFFLINE_MODE=true \
        PATH="$clean_path" \
        TERM=xterm-256color \
        ${plasma-wiki}/bin/wiki "$@"
    }

    test "$(run_fractal --version)" = "1.0.0"
    run_fractal --help > "$TMPDIR/fractal-help.txt"
    run_wiki --help > "$TMPDIR/wiki-help.txt"
    test -s "$TMPDIR/fractal-help.txt"
    test -s "$TMPDIR/wiki-help.txt"

    test -f ${plasma-fractal}/share/skills/fractal/SKILL.md
    test -f ${plasma-fractal}/share/skills/fractal/agents/openai.yaml
    test -f ${plasma-wiki}/share/skills/wiki/SKILL.md
    test -f ${plasma-wiki}/share/skills/wiki/agents/openai.yaml

    fractal_roots=(${plasma-fractal}/lib/python*/site-packages/fractal)
    wiki_roots=(${plasma-wiki}/lib/python*/site-packages/wiki)
    test "''${#fractal_roots[@]}" -eq 1
    test "''${#wiki_roots[@]}" -eq 1
    fractal_root="''${fractal_roots[0]}"
    wiki_root="''${wiki_roots[0]}"
    test -f "$fractal_root/_node/NODE.md"
    test -f "$fractal_root/_scripts/start.sh"
    test -f "$fractal_root/core/schema.sql"
    test -f "$fractal_root/tui/app.tcss"
    test -f "$wiki_root/_assets/git/merge_index.sh"

    repo="$TMPDIR/fractal_smoke_repo"
    mkdir -p "$repo"
    ${git}/bin/git -C "$repo" init -b main
    ${git}/bin/git -C "$repo" config user.name "Fractal Smoke"
    ${git}/bin/git -C "$repo" config user.email "fractal-smoke@example.invalid"
    touch "$repo/.gitignore"
    ${git}/bin/git -C "$repo" add .gitignore
    ${git}/bin/git -C "$repo" commit -m baseline

    cd "$repo"
    run_fractal init --agent=codex
    test -f .fractal/main/config.json
    test -f .fractal/main/.db
    test -f wiki/_index.md
    grep -F '# >>> fractal >>>' .git/info/exclude

    run_fractal commit "initialize fractal" --init
    run_fractal node init smoke --max-iters=1 \
      > "$TMPDIR/node-init-stdout.txt" \
      2> "$TMPDIR/node-init-stderr.txt"
    cat "$TMPDIR/node-init-stdout.txt" "$TMPDIR/node-init-stderr.txt" \
      > "$TMPDIR/node-init-output.txt"
    if grep -F 'Could not download' "$TMPDIR/node-init-output.txt"; then
      cat "$TMPDIR/node-init-output.txt" >&2
      exit 1
    fi
    test -f .worktrees/main.smoke/.fractal/main.smoke/config.json
    run_fractal node list > "$TMPDIR/node-list.txt"
    grep -F "main.smoke" "$TMPDIR/node-list.txt"

    mkdir -p "$out"
    cp "$TMPDIR/fractal-help.txt" "$TMPDIR/wiki-help.txt" \
      "$TMPDIR/node-init-output.txt" "$TMPDIR/node-list.txt" "$out/"
  ''
```

The test intentionally invokes the applications through an almost-empty environment. The application wrappers, not the test's `PATH`, must supply Git, Wiki, Bash, GNU tools, `ps`, tmux, and Fractal's self-reentry path.

- [ ] **Step 3: Register the check while the package is still absent**

In `/Users/johnw/src/ai-nix/flake.nix`, add this attribute beside the existing `build`, `format`, and `tests` checks:

```nix
fractal-smoke = pkgs.callPackage ./overlays/tests/plasma-fractal-smoke.nix { };
```

- [ ] **Step 4: Format the test registration**

Run:

```bash
cd /Users/johnw/src/ai-nix
nixfmt flake.nix overlays/tests/plasma-fractal-smoke.nix
```

Expected: both files format without errors.

- [ ] **Step 5: Run the focused check and verify the expected red state**

Run:

```bash
cd /Users/johnw/src/ai-nix
system=$(nix eval --impure --raw --expr builtins.currentSystem)
nix build --no-link --no-write-lock-file "path:.#checks.${system}.fractal-smoke"
```

Expected: evaluation fails because `callPackage` cannot supply `plasma-fractal` or `plasma-wiki`. The failure must name the missing package argument; a Nix parse error is not an acceptable red state.

- [ ] **Step 6: Review the red test without committing**

Run:

```bash
git diff --check
git diff -- flake.nix overlays/tests/plasma-fractal-smoke.nix
```

Expected: only the smoke test and its check registration appear. Do not commit.

---

### Task 2: Implement the two wheel packages and runtime closure

**Files:**
- Create: `/Users/johnw/src/ai-nix/overlays/30-fractal.nix`
- Modify: `/Users/johnw/src/ai-nix/flake.nix` in the overlay list
- Test: `/Users/johnw/src/ai-nix/overlays/tests/plasma-fractal-smoke.nix`

**Interfaces:**
- Consumes: Nixpkgs Python 3.14 packages `rich`, `textual`, and `typer`; Nixpkgs runtime tools.
- Produces: `pkgs.plasma-wiki`, `pkgs.plasma-fractal`, `bin/wiki`, `bin/fractal`, and stable `share/skills` roots.

- [ ] **Step 1: Create the focused overlay with exact package definitions**

Create `/Users/johnw/src/ai-nix/overlays/30-fractal.nix` with:

```nix
# overlays/30-fractal.nix
# Purpose: Plasma Fractal agent orchestration and its Wiki companion
# Dependencies: Python package set plus standard Unix runtime tools
# Packages: plasma-fractal, plasma-wiki
final: prev:

let
  inherit (prev) lib;
  ps = final.python3Packages;

  wikiRuntime = [
    prev.bash
    prev.coreutils
    prev.gawk
    prev.git
    prev.gnugrep
  ];

  plasmaWiki = ps.buildPythonApplication rec {
    pname = "plasma-wiki";
    version = "1.1.0";
    format = "wheel";

    src = ps.fetchPypi {
      pname = "plasma_wiki";
      inherit version;
      format = "wheel";
      dist = "py3";
      python = "py3";
      hash = "sha256-kZ5f3RrBoxK6GXs5xm+Ug7LcyS91XCY0CHkdkKssZys=";
    };

    dependencies = [ ps.typer ];
    nativeBuildInputs = [ prev.makeWrapper ];
    makeWrapperArgs = [
      "--prefix PATH : ${lib.makeBinPath wikiRuntime}"
    ];

    postInstall = ''
      mkdir -p "$out/share/skills"
      ln -s "$out/${ps.python.sitePackages}/wiki/skills/wiki" \
        "$out/share/skills/wiki"
    '';

    doCheck = false;
    pythonImportsCheck = [ "wiki" ];
    doInstallCheck = true;
    installCheckPhase = ''
      runHook preInstallCheck
      test -f "$out/share/skills/wiki/SKILL.md"
      test -f "$out/share/skills/wiki/agents/openai.yaml"
      "$out/bin/wiki" --help > /dev/null
      runHook postInstallCheck
    '';

    meta = {
      description = "Local-first Markdown wiki and knowledge graph CLI";
      homepage = "https://github.com/plasma-ai/wiki";
      license = lib.licenses.asl20;
      mainProgram = "wiki";
      platforms = lib.platforms.unix;
    };
  };

  fractalRuntime = [
    plasmaWiki
    prev.bash
    prev.coreutils
    prev.gawk
    prev.git
    prev.gnugrep
    prev.gnused
    prev.procps
    prev.tmux
  ];
in
{
  plasma-wiki = plasmaWiki;

  plasma-fractal = ps.buildPythonApplication rec {
    pname = "plasma-fractal";
    version = "1.0.0";
    format = "wheel";

    src = ps.fetchPypi {
      pname = "plasma_fractal";
      inherit version;
      format = "wheel";
      dist = "py3";
      python = "py3";
      hash = "sha256-ROekeFUmslh7y2h/cOMv7d2CCAc8PGxiJ7zNvr7pDoA=";
    };

    dependencies = [
      plasmaWiki
      ps.rich
      ps.textual
      ps.typer
    ];
    nativeBuildInputs = [ prev.makeWrapper ];
    makeWrapperArgs = [
      "--prefix PATH : ${lib.makeBinPath fractalRuntime}"
    ];

    postInstall = ''
      mkdir -p "$out/share/skills"
      ln -s "$out/${ps.python.sitePackages}/fractal/skills/fractal" \
        "$out/share/skills/fractal"
    '';

    postFixup = ''
      wrapProgram "$out/bin/fractal" --prefix PATH : "$out/bin"
    '';

    doCheck = false;
    pythonImportsCheck = [
      "fractal"
      "fractal.tui"
    ];
    doInstallCheck = true;
    installCheckPhase = ''
      runHook preInstallCheck
      test "$("$out/bin/fractal" --version)" = "${version}"
      test -f "$out/share/skills/fractal/SKILL.md"
      test -f "$out/share/skills/fractal/agents/openai.yaml"
      "$out/bin/fractal" --help > /dev/null
      runHook postInstallCheck
    '';

    meta = {
      description = "Hierarchical agent loops with recursive self-organization";
      homepage = "https://github.com/plasma-ai/fractal";
      license = lib.licenses.asl20;
      mainProgram = "fractal";
      platforms = [
        "aarch64-darwin"
        "aarch64-linux"
        "x86_64-linux"
      ];
    };
  };
}
```

- [ ] **Step 2: Register the overlay**

In `/Users/johnw/src/ai-nix/flake.nix`, insert:

```nix
(import ./overlays/30-fractal.nix)
```

immediately after `30-agent-deck.nix` and before the generic Python and inference overlays. No input or lock change is needed.

- [ ] **Step 3: Format the package implementation**

Run:

```bash
cd /Users/johnw/src/ai-nix
nixfmt flake.nix overlays/30-fractal.nix overlays/tests/plasma-fractal-smoke.nix
```

Expected: no formatter errors.

- [ ] **Step 4: Run the focused smoke check and verify green**

Run:

```bash
cd /Users/johnw/src/ai-nix
system=$(nix eval --impure --raw --expr builtins.currentSystem)
nix build --no-link --print-build-logs --no-write-lock-file "path:.#checks.${system}.fractal-smoke"
```

Expected: both wheel derivations build, package install checks pass, and `plasma-fractal-smoke` succeeds after creating a user node and an unstarted child node.

If the wheel builder rejects `format = "wheel"`, inspect the pinned Nixpkgs `buildPythonApplication` interface and adjust only to its authoritative wheel-mode spelling; do not switch to source or an installer.

- [ ] **Step 5: Verify package boundaries directly**

Run:

```bash
cd /Users/johnw/src/ai-nix
nix build --no-link --print-out-paths --no-write-lock-file \
  --impure --expr '
    let
      f = builtins.getFlake "path:/Users/johnw/src/ai-nix";
      pkgs = import f.inputs.nixpkgs {
        system = builtins.currentSystem;
        overlays = [ f.overlays.default ];
      };
    in pkgs.plasma-fractal
  '
```

Expected: one `plasma-fractal-1.0.0` store path. Confirm `flake.lock` remains byte-identical with `git diff --exit-code -- flake.lock`.

- [ ] **Step 6: Run focused lint and review without committing**

Run:

```bash
cd /Users/johnw/src/ai-nix
nix run path:.#format-check
nix run path:.#lint
git diff --check
git diff -- flake.nix overlays/30-fractal.nix overlays/tests/plasma-fractal-smoke.nix
```

Expected: all checks pass and the diff contains only the package, check, and overlay registration. Do not commit.

---

### Task 3: Expose named packages and include Fractal in the default toolchain

**Files:**
- Modify: `/Users/johnw/src/ai-nix/scripts/test.sh`
- Modify: `/Users/johnw/src/ai-nix/flake.nix` in `aiPackagesFor` and `packages`
- Modify: `/Users/johnw/src/ai-nix/README.md`
- Test: `/Users/johnw/src/ai-nix/scripts/test.sh`

**Interfaces:**
- Consumes: `pkgs.plasma-wiki` and `pkgs.plasma-fractal` from Task 2.
- Produces: `packages.<system>.plasma-wiki`, `packages.<system>.plasma-fractal`, and both commands in `packages.<system>.default` and the development shell.

- [ ] **Step 1: Add named-output assertions before defining those outputs**

Append these checks after the existing default-package and dev-shell evaluations in `/Users/johnw/src/ai-nix/scripts/test.sh`:

```bash
test "$("${nix_cmd[@]}" eval --raw ".#packages.${system}.plasma-wiki.version")" = "1.1.0"
test "$("${nix_cmd[@]}" eval --raw ".#packages.${system}.plasma-fractal.version")" = "1.0.0"
```

- [ ] **Step 2: Run the test and verify the named outputs are red**

Run:

```bash
cd /Users/johnw/src/ai-nix
tmp=$(mktemp -d /tmp/ai-nix-test-source.XXXXXX)
rsync -a --exclude=.git --exclude=.direnv --exclude=build --exclude='result*' ./ "$tmp/"
AI_NIX_ROOT="$tmp" bash "$tmp/scripts/test.sh"
status=$?
rm -rf "$tmp"
exit "$status"
```

Expected: failure that `packages.<current-system>.plasma-wiki` or `plasma-fractal` does not exist. The package overlay itself should already evaluate. The Git-free copy is required because the test script evaluates `.#` internally and a Git flake omits new untracked files.

- [ ] **Step 3: Add both packages to `aiPackagesFor`**

In `/Users/johnw/src/ai-nix/flake.nix`, add these lines among the optional AI tools:

```nix
++ opt "plasma-wiki"
++ opt "plasma-fractal"
```

Keep Wiki before Fractal. Do not add Nixpkgs' `fractal` attribute.

- [ ] **Step 4: Expose both named outputs**

Change the per-system `packages` result from a single `default` attribute to:

```nix
{
  default = pkgs.buildEnv {
    name = "ai-nix-toolchain";
    paths = aiPackagesFor pkgs;
    ignoreCollisions = true;
  };
  inherit (pkgs) plasma-fractal plasma-wiki;
}
```

- [ ] **Step 5: Document the installed surface and the intentional skill deferral**

Add this bullet to the current tool inventory in `/Users/johnw/src/ai-nix/README.md`, after the `agent-deck` entry:

```markdown
- Plasma Fractal and its `wiki` companion, providing hierarchical agent loops
  in Git worktrees and tmux. The package includes complete upstream `fractal`
  and `wiki` skill trees but does not install them into agent homes; skill
  selection is owned by the separate Nix-managed agent configuration.
```

Add a short note under **Updating**:

```markdown
Fractal is exposed as `plasma-fractal` because Nixpkgs already uses `fractal`
for the GNOME Matrix client. Keep the Fractal and Wiki package versions and
skill-resource checks aligned when updating either wheel.
```

- [ ] **Step 6: Format and run the now-green source tests**

Run:

```bash
cd /Users/johnw/src/ai-nix
nix run path:.#format -- flake.nix scripts/test.sh
tmp=$(mktemp -d /tmp/ai-nix-test-source.XXXXXX)
rsync -a --exclude=.git --exclude=.direnv --exclude=build --exclude='result*' ./ "$tmp/"
AI_NIX_ROOT="$tmp" bash "$tmp/scripts/test.sh"
status=$?
rm -rf "$tmp"
exit "$status"
```

Expected: exact version assertions pass. Inspect `git diff -- scripts/test.sh` to ensure formatting did not alter unrelated lines; this file already uses tabs and should remain consistent.

- [ ] **Step 7: Build each named output and the default closure**

Run:

```bash
cd /Users/johnw/src/ai-nix
nix build --no-link --print-build-logs path:.#plasma-wiki
nix build --no-link --print-build-logs path:.#plasma-fractal
nix build --no-link --print-build-logs path:.#default
```

Expected: all three builds succeed and no `bin/fractal` collision is reported.

- [ ] **Step 8: Review without committing**

Run:

```bash
cd /Users/johnw/src/ai-nix
git diff --check
git status --short
git diff -- flake.nix scripts/test.sh README.md
```

Expected: only approved Fractal integration and documentation changes. Do not commit.

---

### Task 4: Select Fractal and Wiki in the shared Nix package list

**Files:**
- Modify: `/Users/johnw/src/nix/config/packages.nix` in the AI and LLM tools section
- Test: existing standalone Home Manager evaluation in `/Users/johnw/src/nix/flake.nix`

**Interfaces:**
- Consumes: local `ai-nix` overlay attributes `pkgs.plasma-wiki` and `pkgs.plasma-fractal`.
- Produces: both packages in shared `package-list` for Darwin and standalone Linux consumers when available.

- [ ] **Step 1: Establish the failing consumer-selection check**

Run before editing `config/packages.nix`:

```bash
cd /Users/johnw/src/nix
nix eval \
  --no-write-lock-file \
  --override-input ai-nix path:/Users/johnw/src/ai-nix \
  --json \
  '.#homeConfigurations."johnw@aarch64-linux".config.home.packages' \
  --apply 'packages: map (package: package.name) packages' \
  > /tmp/fractal-home-packages-before.json
if grep -q 'plasma-fractal-1.0.0' /tmp/fractal-home-packages-before.json; then
  echo 'unexpected: plasma-fractal is already selected' >&2
  exit 1
fi
if grep -q 'plasma-wiki-1.1.0' /tmp/fractal-home-packages-before.json; then
  echo 'unexpected: plasma-wiki is already selected' >&2
  exit 1
fi
```

Expected: evaluation succeeds and both explicit assertions confirm that the consumer has not selected the new packages.

- [ ] **Step 2: Add the minimal package selections**

In the AI and LLM tools section of `/Users/johnw/src/nix/config/packages.nix`, add:

```nix
++ optPkg "plasma-wiki"
++ optPkg "plasma-fractal"
```

Place both after the local inference packages and before agent-specific package selections. Preserve the existing `ccstatusline` and all unrelated package entries.

- [ ] **Step 3: Format only the changed Nix file**

Run:

```bash
cd /Users/johnw/src/nix
nixfmt config/packages.nix
```

Expected: no unrelated file changes.

- [ ] **Step 4: Re-run the consumer-selection check and verify green**

Run:

```bash
cd /Users/johnw/src/nix
nix eval \
  --no-write-lock-file \
  --override-input ai-nix path:/Users/johnw/src/ai-nix \
  --json \
  '.#homeConfigurations."johnw@aarch64-linux".config.home.packages' \
  --apply 'packages: map (package: package.name) packages' \
  > /tmp/fractal-home-packages-after.json
grep -q 'plasma-wiki-1.1.0' /tmp/fractal-home-packages-after.json
grep -q 'plasma-fractal-1.0.0' /tmp/fractal-home-packages-after.json
```

Expected: both `grep` commands succeed.

- [ ] **Step 5: Evaluate the second standalone Linux architecture and Hera without activating**

Run:

```bash
cd /Users/johnw/src/nix
nix eval --no-write-lock-file \
  --override-input ai-nix path:/Users/johnw/src/ai-nix \
  --raw '.#homeConfigurations."jwiegley@x86_64-linux".activationPackage.name'
nix eval --no-write-lock-file \
  --override-input ai-nix path:/Users/johnw/src/ai-nix \
  --raw '.#darwinConfigurations.hera.system.name'
```

Expected: both configurations evaluate and print derivation names. Do not build or switch either configuration.

- [ ] **Step 6: Run focused consumer-repository checks**

Run:

```bash
cd /Users/johnw/src/nix
nixfmt --check config/packages.nix
statix check config/packages.nix
deadnix --no-lambda-arg --no-lambda-pattern-names --no-underscore --fail config/packages.nix
nix flake check --no-build --no-write-lock-file \
  --override-input ai-nix path:/Users/johnw/src/ai-nix
git diff --check
```

Expected: all checks pass; neither lock file changes.

- [ ] **Step 7: Review without committing**

Run:

```bash
git -C /Users/johnw/src/nix diff -- config/packages.nix
git -C /Users/johnw/src/nix status --short --branch
```

Expected: exactly two package-selection lines plus formatter-only positioning if required. Do not commit.

---

### Task 5: Run cross-platform evaluation and final verification

**Files:**
- Verify all files from Tasks 1–4
- Verify: `/Users/johnw/src/ai-nix/flake.lock`
- Verify: `/Users/johnw/src/nix/flake.lock`
- Verify: `/Users/johnw/dl/fractal-nix-skills-management-handoff.md`

**Interfaces:**
- Consumes: completed package and consumer integrations.
- Produces: fresh evidence that the implementation meets the approved specification without activation.

- [ ] **Step 1: Evaluate both named packages on every declared system**

Run:

```bash
cd /Users/johnw/src/ai-nix
for system in aarch64-darwin aarch64-linux x86_64-linux; do
  test "$(nix eval --raw "path:.#packages.${system}.plasma-wiki.version")" = "1.1.0"
  test "$(nix eval --raw "path:.#packages.${system}.plasma-fractal.version")" = "1.0.0"
done
```

Expected: all six assertions pass.

- [ ] **Step 2: Run the complete `ai-nix` verification surface**

Run:

```bash
cd /Users/johnw/src/ai-nix
nix run path:.#format-check
nix run path:.#lint
nix flake check --print-build-logs path:.

tmp=$(mktemp -d /tmp/ai-nix-final-source.XXXXXX)
rsync -a --exclude=.git --exclude=.direnv --exclude=build --exclude='result*' ./ "$tmp/"
status=0
AI_NIX_ROOT="$tmp" bash "$tmp/scripts/test.sh" || status=$?
if [ "$status" -eq 0 ]; then
  AI_NIX_ROOT="$tmp" bash "$tmp/scripts/no-warnings.sh" || status=$?
fi
rm -rf "$tmp"
exit "$status"
```

Expected: all commands exit zero. If a broad check fails, diagnose and fix the root cause; do not disable or bypass it.

- [ ] **Step 3: Verify the package behavior from its named output**

Run:

```bash
cd /Users/johnw/src/ai-nix
fractal_out=$(nix build --no-link --print-out-paths path:.#plasma-fractal)
wiki_out=$(nix build --no-link --print-out-paths path:.#plasma-wiki)
test "$($fractal_out/bin/fractal --version)" = "1.0.0"
test -f "$fractal_out/share/skills/fractal/SKILL.md"
test -f "$wiki_out/share/skills/wiki/SKILL.md"
```

Expected: all assertions pass.

- [ ] **Step 4: Re-run consumer evaluation and static checks**

Run:

```bash
cd /Users/johnw/src/nix
nixfmt --check config/packages.nix
statix check config/packages.nix
deadnix --no-lambda-arg --no-lambda-pattern-names --no-underscore --fail config/packages.nix
nix flake check --no-build --no-write-lock-file \
  --override-input ai-nix path:/Users/johnw/src/ai-nix
```

Expected: all commands exit zero.

- [ ] **Step 5: Confirm locks and deferred skill ownership remain untouched**

Run:

```bash
git -C /Users/johnw/src/ai-nix diff --exit-code -- flake.lock
git -C /Users/johnw/src/nix diff --exit-code -- flake.lock
git -C /Users/johnw/src/nix diff --name-only | grep -E '(^|/)(skills|prompts|catalog)' && exit 1 || true
test -f /Users/johnw/dl/fractal-nix-skills-management-handoff.md
```

Expected: both lock checks pass, no managed-skill implementation changed, and the handoff report exists.

- [ ] **Step 6: Inspect final diffs and repository status**

Run:

```bash
git -C /Users/johnw/src/ai-nix diff --check
git -C /Users/johnw/src/ai-nix status --short --branch
git -C /Users/johnw/src/ai-nix diff --stat
git -C /Users/johnw/src/nix diff --check
git -C /Users/johnw/src/nix status --short --branch
git -C /Users/johnw/src/nix diff --stat
```

Expected: only the approved Fractal packaging, tests, docs, and two consumer package selections appear. Do not commit, switch, or activate.
