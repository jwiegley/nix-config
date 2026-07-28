# Fleet Programme Implementation — Handoff

**Updated:** 2026-07-28
**Plan:** `doc/FLEET-IMPL-WIGGUM-PLAN.md` (frozen)
**Branch:** `impl/fleet-programme` in the worktree `/Users/johnw/src/nix-impl`
**Tracking:** [project 9](https://github.com/users/jwiegley/projects/9)

## Concurrency — read this before touching anything

`~/src/nix` has a **live concurrent autonomous writer** (a `pi` session, PID 28771
at session start, committing to `main` and snapshotting roughly every two minutes).
There are five worktrees on this repository. Therefore:

- Do all work in `/Users/johnw/src/nix-impl`. Never `git add` from `~/src/nix`.
- Before the terminal `merge --ff-only`, re-check that `main` has not moved and that
  the other writer has no uncommitted state. Abort rather than disturb it.

**A hazard was hit and fixed here.** `bin/publish-test.py` built its git environment
from `os.environ`. Under a git hook that inherits `GIT_DIR`/`GIT_INDEX_FILE`, so
`git init --bare <tmpdir>` wrote `core.bare = true` into the *real*
`~/src/nix/.git/config` and broke **all five worktrees at once**
(`fatal: this operation must be run in a work tree`). `cwd=` is not protection — an
explicit `GIT_DIR` beats it. Fixed by a `clean_env()` scrub of 13 `GIT_*` variables,
locked in by a regression test verified to fail when the scrub is removed. If it ever
recurs: `git config core.bare false`, then confirm `git worktree list` shows `[main]`
rather than `(bare)`.

## Closed this session

| Issue | What landed |
|---|---|
| `nix-config#16` | vps unarmed **and** lock bumped `1b71b192 → e0ed94fa`, plus a consumer canary. Fix and bump had to be one commit: the corrected call is wrong at the old rev. |
| `nix-config#18` | `bin/publish` — dual-remote guard, 15 tests, real ephemeral-GPG signing and a `pre-receive` fault injection for the partial-publish path |
| `nix-config#19` | `bin/parity-baseline` + `test/baseline/parity-e0ed94fabbc0.json` |
| `nix-config#21` | Four host facts confirmed live; two new findings (Nix skew, `id -un`) |
| `nix-config#24` | Transitive lock leak closed via `follows` on the obr input; closure `file://` nodes 1 → 0 |
| `nix-config#30` | Bare `nix fmt` fixed; delegates to `bin/quality`; unknown flags exit 2 instead of fake-passing |
| `nix-config#36` | Purity check walks the whole closure; empty allowlist compared as an exact set |
| `nix-config#37` | All eight hosts route; `bin/switch` no longer activates via floating `home-manager/master` |
| `nix-config#46` | `bin/quality` is the single authority for lefthook, CI and the Makefile |
| `nix-config#48` | Eleven false-evidence aliases deleted; contract unfrozen but still catching drift |

## Open with work landed — read the issue comment for the gate

- **`nixos-config#1`** — Stage 2 landed (routing fixed, six packages resolve, canary
  with a proven negative test). **Vulcan was already broken, not armed:** its lock
  had reached `03b5eecc`, 29 commits past `a3cc3843`, and its eval failed outright.
  Stage 1's backward pin is now moot; whether to pin `?rev=` at all is a standing
  policy question put to the user. Remaining: sync the two commits to vulcan's
  `/etc/nixos` and run the native toplevel build. Forcing `toplevel` from hera fails
  only on `/etc/nixos/firmware`, a vulcan-local path.

## Landed after the first merge

| Change | What |
|---|---|
| `0dc8625b` | 42 catalog `update.branch` values corrected — all 98 now resolve |
| `ffe0ec8e` | #24 + #36 together: leak closed, purity deepened to the closure |
| `8dc3dd92` | Four partner observations fixed, one a live activation bug |
| `6b7582fa` | Reverted the `~/.pi` symlink; hera builds again |

**Parity across every commit so far: package multisets IDENTICAL on all seven targets**
(`bin/parity-baseline --compare`, baseline `e0ed94fa` → `c5029775`). drvPath moved only
on the four host toplevels, for the expected additive reason.

### The `bin/switch` bug is the one to learn from

The #37 routing fix *broke the thing it fixed*. `nix_flake_output_for_host` normalizes
its argument, and `bin/switch` passes a value it already normalized.
`hera`/`clio`/`vulcan`/`vps` survive a second pass only by accident of their glob
patterns; `shared-work` did not, so every work machine got a bare `return 1`.

My test missed it because it called the function with **raw hostnames** — never the
normalized label the real caller passes. Normalization is now idempotent by
construction, and the test walks the actual call path.

Generalize this: a test written by whoever wrote the fix tends to exercise the path
they were thinking about, not the path the caller takes. Two of the four partner
observations were of that shape, including a test of mine that was vacuous in exactly
the way I had been flagging in other people's specs.

## Consumer-side state

- `~/src/nixos`: `95198d91` — routing fix + reach-in canary, signed, **not synced to
  vulcan's `/etc/nixos`**. `nixos-config#1`'s last acceptance box needs that.
- `~/src/vps`: `e670518` — unarm + lock bump + canary, signed, not synced.
- `andoria-08` (`~/.config/home-manager`, shared NFS home): `ae65f7a`, unsigned to match
  that repo's own convention. Two pre-existing faults fixed — the missing
  `nixManagedAiHomeClass`, and a `pythonRelaxDeps` boolean where nixpkgs now wants a
  list. Builds; **not switched**. Switching there repoints the profile for all four
  machines at once, so #70 must run first.

## Open decisions blocking specific issues

1. **#78** — `update` is already on PATH from `my-scripts`. The rename collides. Needs
   your call: rename one, retire one, or pick another name.
2. **nixos-config#1** — whether vulcan's inputs should carry `?rev=` pins at all. The
   canary plus #22's gate address the actual failure; a pin is a separate policy.
3. Several issues' acceptance criteria name `./config/fleet`, which does not exist —
   the rename (#47) has not landed. Flagged on #46/#48 rather than silently rewritten.

## Findings worth carrying forward

**The parity oracle's two quantities answer different questions.** Measured: adding
`bin/quality` and `bin/parity-baseline` moved **all four host drvPaths** and moved
**no package multiset** (386/414/367/368 unchanged), because `nix-scripts` packages
`bin/`. The portable drvPaths did not move. So a gate must treat *multiset drift* as
a parity failure and *drvPath-only drift* as a question — additive source changes move
drvPath legitimately, while a pure refactor should not. `--check` is strict same-rev
determinism; `--compare` separates the two categories.

**The derived baseline contradicts the corpus's asserted counts.** hera is **414**,
not 412; the portable systems are **30/30/30**, not 43/37/38. The derived values are
now the oracle, which is exactly what #19 asked for.

**Every gate in this repo needs its negative case run.** Four separate defects this
session were checks that reported success while covering nothing: the shfmt loop that
swallowed mid-loop failures, `nix fmt` reading stdin, eleven aliased checks, and my own
`bin/quality` summary undercounting via a subshell. Each was found by asking "does this
fail when it should?" — never by reading the code.

## Not started

Everything else in project 9 — 53 issues. The next natural units:

1. **#24 + #36 together.** #36 deepens the lock-purity check to the whole closure,
   which will *fail* on the `obr → org2jsonl` `file://` leak that #24 owns. The
   sequencing decision (land the check with a referenced known-failure entry, or land
   #24 first) is recorded in the #36 spec and is not yet made.
2. **#35** — de-interpolate `vars.gitPkg`. Highest parity risk in the batch; the
   oracle now exists to gate it. The adversarial pass returned `needs-correction`;
   read that before starting.
3. **#27** — delete the inert `config/hera.nix`/`config/clio.nix` stubs. Spec is
   sound *except* its parity claim: `flake.nix:352` uses `src = self.outPath`, so the
   formatting/linting check drvPaths do move. Benign, but the claim needs correcting.

Specs and adversarial verdicts for all seven of the first batch are in the workflow
journal (`wf_eeaf009d-c1e`), extracted per-issue under the session scratchpad.

## Attempt counters

| Gate | Attempts | Status |
|---|---|---|
| `bin/quality` (all fast suites) | 1 | **PASS** — 94 nix, 32 shell, 36 python, 4 suites |
| `nix flake check ./config/ai --all-systems --no-build` | 2 | **PASS** both |
| `python3 -m unittest bin/update-overlay-test.py` | 3 | **PASS** 25 tests |
| `python3 -m unittest bin/publish-test.py` | 5 | **PASS** 16 tests |
| Signed commit through lefthook | 4 | **PASS** after the `GIT_DIR` fix (3 aborts, all one root cause) |
| vulcan cherry-pick eval | 2 | **PASS** — six packages resolve |
| vps toplevel eval | 1 | **PASS** — `nixos-system-vps-…drv` |
| parity determinism (`--check`, same rev) | 2 | **not yet proven** — both runs interrupted; re-run pending |

## Authorization still outstanding

- **No push.** `main`, `origin` and `github` were all level at session start; the
  earlier report of 6/47 unpushed was from stale tracking refs and is corrected.
- **No activation**, on any host. `~/src/nixos` and `~/src/vps` carry signed commits
  that have not been synced to their authoritative `/etc/nixos` checkouts.

## Audit corrections that could not be amended into their commits

An independent audit of `601c7cf7`, `71805147` and `9d00d47e` found two numeric
errors in the commit messages' own `bin/quality` evidence blocks. Both commits are
already merged into `main`, and rewriting merged history requires explicit
authorization per `CLAUDE.md`, so the corrections are recorded here instead of
amended away.

| commit | claimed | **actual at that tree** |
|---|---|---|
| `601c7cf7` | 32 shell files | **34** |
| `9d00d47e` | 94 nix files | **93** |

The cause is consistent and worth naming, because it will recur otherwise: in each
commit the **one dimension that changed** is reported at its pre-change value while
every unchanged dimension is correct. I ran `bin/quality` *before* `git add`, and
`bin/quality` discovers scope via `git ls-files`, which cannot see untracked files.
So the evidence block measured the parent tree and was then presented as proof of
the commit's own state.

The suites do pass at the committed states — this is misattributed evidence rather
than a failing gate — but presenting a parent-tree measurement as a commit's
proof-of-green is exactly the overstatement this programme rejects.

**Rule going forward: stage first, then measure.** An evidence block must be
captured after `git add`, or it describes a tree that was never committed.

Two smaller corrections from the same audit:

- **"Fully offline" was wrong** in the #22 closing comment. `--offline` is opt-in
  via `CONSUMER_EVAL_OFFLINE=1`; the wired `bin/quality consumer-eval` does not set
  it. Corrected on the issue.
- **The vacuous-green tally is inconsistent** across messages — "four times" in one,
  "five times" in another. Five is right, and the count is now: the shfmt loop, the
  stdin-reading formatter, the eleven aliased outputs, the subshell accumulator, and
  the routing test called with the wrong input shape. A sixth has since been added
  by me and fixed: the null-`repoHead` check I verified with a flag that does not
  exist.
- `601c7cf7`'s "166 = 125 + 22 + 8 + 7" sums to 162. Each figure is right; the
  enumeration omits the 4 `flake-ai-internal-consumer` references.
