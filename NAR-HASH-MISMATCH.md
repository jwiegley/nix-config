# NAR Hash Mismatch in Local Git Flake Inputs

## The Bug

Nix uses two different code paths to process `git+file://` flake inputs, and they
can produce different NAR hashes for the same git commit:

| Operation | Code Path | Reads From |
|-----------|-----------|------------|
| `nix flake update` (locking) | Source-path walker | Local **filesystem** |
| `darwin-rebuild switch` (evaluation) | `git archive` | Git **tree objects** |

When any file exists in the git tree but is **missing from the local filesystem**,
these two paths produce different NARs. The locking step writes hash A to
`flake.lock`, the evaluation step computes hash B, and Nix rejects the mismatch:

```
error: NAR hash mismatch in input 'git+file:///Users/johnw/src/scripts?...'
    expected 'sha256-...'
    but got 'sha256-...'
```

This is a Nix bug (NixOS/nix#13698), not a configuration error.

## Known Triggers

### 1. `skip-worktree` flagged files

Git's `skip-worktree` flag tells git to keep a file in the index/tree but **not
check it out to disk**. Crucially, `git status` hides the discrepancy — it
reports "working tree clean" even though tracked files are missing.

**How it happens:** Tools like `beads` (`bd`, a git-based issue tracker) set
`skip-worktree` on their data files (e.g., `.beads/issues.jsonl`) so that local
modifications don't show up in `git status`. If the tool isn't installed or the
files were never checked out, the directory doesn't exist on disk.

**Example (2026-03-18):** The `scripts` repo had `.beads/interactions.jsonl` and
`.beads/issues.jsonl` with both `skip-worktree` and `assume-unchanged` flags.
The `.beads/` directory didn't exist on disk. Result:

- `nix flake update scripts` (filesystem walker) — `.beads/` not on disk, excluded from NAR
- `darwin-rebuild switch` (git archive) — `.beads/` in tree, included in NAR
- Different NARs, different hashes, persistent mismatch error

**Detection:**
```bash
git ls-files -v | grep -E '^[shS] '
```
- `S` = skip-worktree only
- `s` = skip-worktree + assume-unchanged
- `h` = assume-unchanged only

**Fix:**
```bash
git update-index --no-skip-worktree --no-assume-unchanged <files>
git checkout -- <files>
```

### 2. `assume-unchanged` flagged files

Same mechanism as `skip-worktree`. The `assume-unchanged` flag tells git to skip
stat checks on a file. If the file is deleted from disk, git won't notice.

**Detection:** Same as above — lowercase `h` in `git ls-files -v`.

**Fix:** Same as above.

### 3. Uninitialized git submodules

A submodule registered in `.gitmodules` with a gitlink entry in the tree, but
never initialized locally (`git submodule init` / `git submodule update`).

**How it happens:** A submodule is added to a repo but not initialized on all
machines. The gitlink (mode 160000) exists in the tree but the directory is empty
on disk.

**Example (2026-03-16):** The `promptdeploy` repo had a submodule
`skills/humanizer` that was never initialized locally.

- Source-path walker: empty dir on disk with zero children, **skipped entirely**
- Git archive: directory present in tree, **included as empty directory**
- Different NARs

**Detection:**
```bash
git submodule status | grep '^-'
```
The `-` prefix means uninitialized.

**Fix:** Either initialize the submodule or remove it:
```bash
# Option A: Initialize
git submodule update --init

# Option B: Remove
git rm <submodule-path>
git commit -m "Remove unused submodule"
```

### 4. Initialized submodules (gitlinks)

Even when a submodule is fully initialized and checked out, it can still cause
NAR hash divergence. The two Nix code paths disagree on how to handle the
gitlink entry (mode `160000`):

- **Source-path walker**: Skips submodule directories entirely (treats them as
  nested repositories outside the current tree)
- **Git archive**: Includes the gitlink as an empty directory

This produces different directory counts and therefore different NAR hashes.

**How it happens:** A submodule is properly initialized and working, so
`git status` and `git submodule status` both look clean. No flags are set.
But the structural disagreement between the two code paths persists silently.

**Example (2026-03-19):** The `trade-journal` repo had `vendor/simple-amount`
as an initialized submodule. The source-path walker produced 26 directories
(no `vendor/`), while git archive produced 28 directories (with `vendor/` and
`vendor/simple-amount/` as empty dirs). The hash mismatch was persistent and
could not be fixed by clearing caches alone.

**Detection:**
```bash
git -C /path/to/repo ls-files --stage | grep '^160000'
```
Any output means gitlinks exist and may cause NAR divergence.

**Fix:** Remove the submodule if it's not needed for the Nix build:
```bash
git submodule deinit <submodule-path>
git rm <submodule-path>
rm -rf .git/modules/<submodule-path>
git commit -m "Remove submodule to fix NAR hash divergence"
```

If the submodule is needed, add `?submodules=1` to the flake input URL. This
makes both code paths include the full submodule content, but requires the
submodule to be initialized on all machines.

## The Verification Cache Problem

The mismatch is made worse by Nix's `fetcher-cache-v4.sqlite`, which caches hash
computations separately for user and root:

| Cache | Location | Written by |
|-------|----------|------------|
| User | `~/.cache/nix/fetcher-cache-v4.sqlite` | `nix flake update` |
| Root | `/var/root/.cache/nix/fetcher-cache-v4.sqlite` | `sudo darwin-rebuild` |

Each cache stores `sourcePathToHash` entries keyed by `{rev}` (source-path
walker result) and `{rev};e` (git-archive/exportIgnore result). When the two
methods disagree, the caches contain conflicting hashes, and the mismatch
persists across runs until the caches are cleared or the underlying cause is
fixed.

**Never run `sudo nix flake update` or `sudo nix flake lock`** — this populates
root's cache with hashes that may diverge from the user's.

## Automated Prevention

The Makefile includes a `verify-inputs` target that runs automatically before
`lock-local` (and thus before `switch`). It scans all local `git+file://` inputs
for:

- Files with `skip-worktree` or `assume-unchanged` flags
- Uninitialized submodules
- Any submodule gitlinks (mode `160000`) that may cause structural NAR divergence

If any are found, it blocks the build with specific error messages and fix
instructions.

### Manual check for any machine

To check all local git repos that are flake inputs:

```bash
# From ~/src/nix (or wherever your flake lives):
make verify-inputs
```

To check a single repo:

```bash
# skip-worktree / assume-unchanged
git -C /path/to/repo ls-files -v | grep -E '^[shS] '

# Uninitialized submodules
git -C /path/to/repo submodule status 2>/dev/null | grep '^-'
```

### Comparing the two code paths directly

If you suspect a NAR hash mismatch but aren't sure of the cause, you can diff
what the two Nix code paths see:

```bash
REPO=/path/to/repo
TMPDIR_A=$(mktemp -d)
TMPDIR_B=$(mktemp -d)

# Git archive (what darwin-rebuild sees)
git -C "$REPO" archive HEAD | tar -C "$TMPDIR_A" -xf -

# Checkout-index (what nix flake update sees)
GIT_WORK_TREE="$TMPDIR_B" git -C "$REPO" checkout-index -a

# Compare
diff -rq "$TMPDIR_A" "$TMPDIR_B"

# Clean up
rm -rf "$TMPDIR_A" "$TMPDIR_B"
```

Any files listed as "Only in" one directory are the source of the mismatch.

## Timeline

| Date | Incident | Trigger | Fix |
|------|----------|---------|-----|
| 2026-03-16 | promptdeploy NAR mismatch | Uninitialized submodule `skills/humanizer` | Removed submodule from repo |
| 2026-03-18 | scripts NAR mismatch | `skip-worktree` on `.beads/*.jsonl` | Cleared flags, restored files |
| 2026-03-18 | — | — | Added `verify-inputs` Makefile target |
| 2026-03-19 | trade-journal NAR mismatch (clio) | Initialized submodule `vendor/simple-amount` (gitlink) | Removed submodule; simple-amount resolved from Hackage |
| 2026-03-19 | — | — | Added gitlink (mode 160000) detection to `verify-inputs` |
