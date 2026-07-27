# Unified Fleet Configuration — Wiggum Handoff

**Plan:** `doc/UNIFIED-CONFIG-WIGGUM-PLAN.md` (frozen)
**Last updated:** 2026-07-27, session start
**Branch:** `main` in `~/src/nix`, 8 commits ahead of `origin/main`

## RESOLVED — concurrent autonomous writer in `~/src/nix`

**Escalated 2026-07-27; user chose worktree isolation. Never commit in `~/src/nix`
from this session.**

**Resolution.** All work for this task happens in a dedicated worktree:

```
/Users/johnw/src/nix          -> main                    (other session, untouched)
/Users/johnw/src/nix-design   -> design/unified-fleet    (this session)
```

Created with `git worktree add /Users/johnw/src/nix-design -b design/unified-fleet
8452497c` — branched from clean HEAD, so it does **not** carry the other session's
uncommitted work. A worktree has its own index and HEAD, so commits here cannot
race theirs. Integration into `main` is the user's call, later.

The two design documents were moved out of `~/src/nix/doc/` into the worktree, so
`~/src/nix` now contains *only* the other session's changes.

Another autonomous session is actively working in this repository:

- **PID 3343** — `claude --model claude-fable-5 --dangerously-skip-permissions
  --resume a92e4ed8-06af-4b74-95ec-382b44db31b4`, started Jul 25 08:08,
  **cwd `/Users/johnw/src/nix`**.
- It is mid-series on the source-catalog migration continuing commits
  `c4332fe6 → 598e1430 → 315291cc → 8a661b96`. Working files written at:
  `sources/pi.json` 11:31, `sources/ai.json` 12:10, `sources/anvil.json` 12:30,
  `sources/tools.json` 12:48 (staged, uncommitted).
- Its in-flight change refactors `mkSimpleGitHubBinary` from
  `version`/`rev`/`sha256` args to a `source` arg sourced from
  `packages/source-catalog.nix`, touching `config/zsh.nix` and seven overlays.

This session's working tree was **clean at 12:46:34** (session start); the
mutation appeared at 12:48. Both plausible internal causes were **eliminated**:

- The unit test suite does **not** mutate the tree — verified by cloning HEAD
  (`8452497c`) into a scratch dir and running `python3 -m unittest
  bin/update-overlay-test.py`: 20 tests pass, `git status` stays empty.
- The analysis workflow's agent transcripts were created at 12:53, *after* the
  12:48 mutation, and contain no mutating commands. The two `web-searcher`
  agents have only Perplexity/WebFetch tools and cannot write files.

**Action taken:** `doc/UNIFIED-CONFIG-WIGGUM-*.md` were briefly `git add`ed into
the shared index, which would have let the other session's next commit sweep them
up. They were unstaged with an explicitly path-scoped
`git restore --staged <those two files>`. The other session's staged
`sources/tools.json` and its nine unstaged working-tree edits were left exactly
as found. Nothing of theirs was reset, restored, stashed, or cleaned.

**Why this blocks committing:** `~/src/nix` has one index and one HEAD. Any
commit from this session races theirs, and either commit can capture the other's
files. Per the repository's own rule — preserve unrelated working-tree changes —
this session holds all commits in `~/src/nix` until the user decides.

Read-only analysis and design work continues safely and is unaffected.

## Tooling state

- Anvil MCP **available** on this host (dedicated backend; `git-status`,
  `file-batch`, `file-outline` probed successfully). Use progressive-disclosure
  reads and batched typed edits for the rest of the loop.
- Repos `~/src/nix`, `~/src/nixos`, `~/src/andoria` all had **clean** working
  trees at session start.
- `doc/observations/` does not exist → no partner observations outstanding.

## Progress

### Done

- **DoD-7 baseline verification — PASSED, output shown.**
  `nix flake check ./config/ai --all-systems --no-build` exit 0, all checks green
  across `aarch64-darwin`, `aarch64-linux`, `x86_64-linux`; captured output is
  reproduced under "DoD-7 evidence" in the plan. `bin/update-overlay-test.py`
  20/20, independently re-run by the `fess` audit with a clean tree before and
  after. `nix fmt` is not applicable — this branch modifies only Markdown.
- External research complete (two `web-searcher` agents) — see
  `doc/UNIFIED-CONFIG-RESEARCH.md`.
- Flake laziness verified empirically; the closure rationale is refuted.
- Both real-flake blockers traced and proven removable (F3a).
- The NFS home-manager state question resolved from home-manager source.
- `fess` audit of `b8fd05f3` complete; its findings folded in.
- Baseline recon of all three repositories.
- Confirmed cross-repo coupling inventory (see Findings below).
- Launched two `web-searcher` agents: flake/monorepo patterns, and host-variance
  plus secrets.
- Froze plan and Definition of Done.

### In flight

- Analysis workflow `wf_fa028b6d-0e0` (`unified-fleet-config-design`): all five
  dimension analyses returned; three adversarial claim verifiers running; then
  three design proposals → three judge lenses → synthesis + completeness critic.
  Script and transcripts under the session's `workflows/` directory; resume with
  `Workflow({scriptPath, resumeFromRunId: "wf_fa028b6d-0e0"})`.
- Secondary follow-up to `research-variance-secrets` on systemd-user lingering
  for the NFS Ubuntu hosts (whether `loginctl enable-linger` is required for
  sops-nix/agenix secrets to exist before first interactive login).

### Not started

- PAL consensus (DoD-4).
- Design document (DoD-5).
- Staged migration plan (DoD-6).

## Findings so far (evidence-backed)

**F1 — `flake = false` erases the module API.** Both consumers reach into
`nix-config` internals by string path:
- `~/src/nixos/modules/users/home-manager/johnw.nix:26` hand-calls
  `import "${inputs.nix-config}/config/packages.nix"` with hand-assembled args.
- `~/src/nixos/overlays/default.nix:31,298,303,306` and
  `~/src/nixos/flake.nix:313,326` cherry-pick attributes out of *individual
  overlay files*, manually rebuilding `prevWithMyLib` because
  `overlays/00-lib.nix` is an undocumented prerequisite of `30-misc-tools.nix`.
  Overlay composition order is an implicit contract the consumer reproduces by
  hand.
- `~/src/andoria/flake.nix:410` and `:431` do the same for `johnw.nix` and
  `packages.nix` respectively.

**F2 — Each consumer fetches `nix-config` twice, with independently drifting
revisions.** Once as `flake = false` (whole tree) and once as a real flake at
`?dir=config/ai`:
- `~/src/nixos/flake.nix:48` + `:111`
- `~/src/andoria/flake.nix` (`nix-config` + `nix-config-ai`)
`test/ai/lock-coherence.nix` exists to police exactly this drift, but only
inside `nix-config` itself — the consumers have no such check.

**F3 — The stated closure rationale is largely stale, and the real constraint is
different.** `flake.lock` has 431 nodes: 426 `github:`, **1** `git+file://`,
**1** `git+ssh://`, 2 `path:`. Those four buckets sum to 430; the 431st is the
`root` node, which has no `locked` field and so falls into none of them. The two
`path:` nodes are the internal relative subflakes `./config/ai` and
`./config/certs`, correctly not blockers. Counts were independently recounted and
confirmed exact by the `fess` audit, which also verified the identical
431/426/2/2/1 split in `~/src/nix/flake.lock` — the other session has not touched
the lock. The single `git+file://`
(`file:///Users/johnw/src/org2jsonl`) is **transitive**, leaked by the `obr`
input's own lock — the root's own `org2jsonl` is `github:`. `stock-trader` is
`git+ssh://gitea` (LAN-only). So consuming `nix-config` as a *real flake* is
blocked by exactly **two** tractable inputs, not by architecture. Furthermore
the constraint is about **lock-time input resolution**, not closure size: flake
outputs are lazily evaluated, so building one `homeConfigurations` attribute
never realizes `darwinConfigurations.hera`. *(Mechanism to be confirmed in
research — DoD-2.)*

**F4 — The work fleet has no build-time host identity.** `~/src/andoria/flake.nix:71`
hardcodes `hostname = "andoria-08"` and exports a single
`homeConfigurations.jwiegley`, yet serves four machines. True identity is
recovered at *runtime* by shelling out to `hostname` (agent-deck wrapper at
`flake.nix:371`, activation at `:529`). `config/johnw.nix:60-61` acknowledges this:
the comment states the shared flake "supplies `andoria-08` on every NFS client"
(line 63 is the `useHeadlessEmacs` code itself).

The build-time decision
`johnw.anvil.useHeadlessEmacs = lib.mkDefault (lib.elem hostname dedicatedAnvilLinuxHosts)`
is therefore evaluated against a knowingly wrong hostname on three of the four
work machines. **Correction on the consequence:** `config/anvil-hosts.nix`
lists all four work machines (`andoria-08`, `andoria-t2`, `delphi-3bd4`,
`gpu-server`) in `dedicatedLinux`, so the membership test returns `true`
regardless of which of them is being built. This decision is thus *accidentally
correct*, not currently broken. The hazard is latent rather than live: the
moment any one work machine needs to differ on a host-keyed decision, the shared
hostname silently yields the wrong answer with no error. Treat this as a
structural defect, not an outage.

**F4a — `lib.inputSet` is an existing, good partial answer to F5.**
`config/ai/flake.nix:87-90` exports `lib.inputSet = portableInputs` and
`lib.inputNames`, and the root flake consumes it at `flake.nix` via
`portableInputs = rootInputs.nix-config-ai.lib.inputSet;
inputs = rootInputs // portableInputs;`. The subflake therefore owns the
authoritative input set and re-exports it instead of the root duplicating those
declarations, an invariant enforced by
`bin/update-overlay-test.py:887` (`test_root_consumes_portable_input_authority_transitively`).
This "input authority" idea is the right shape and the target design should
generalize it rather than discard it.

**F5 — `inputs` is an unchecked, duck-typed contract.** The core accepts the
consumer's entire `inputs` attrset and probes it (`inputs ? git-ai`,
`inputs.foo or null`, `pkgs ? my-scripts`). Consumers must reverse-engineer the
required set; `~/src/andoria/flake.nix` carries the comment "PAL MCP server
source (needed by nix-config overlay 30-ai-mcp.nix)". `packages.nix`'s
`userPackageInputAllowlist` is the right instinct at the wrong layer.

**F6 — Version skew forces shims in consumers.** Vulcan pins HM `release-25.11`
while `nix-config` tracks HM master. The core uses master-only
`programs.ssh.settings`, so vulcan carries `ssh-settings-compat.nix`, plus a
fake `options.programs.git-ai` freeform stub to satisfy an *unconditional*
assignment in the core for an *optional* input.

**F7 — Variance by override rather than by parameter.** Per-host `lib.mkForce`
undoes core defaults: GPG signing disabled on vulcan, vps, and andoria;
`EDITOR`, `gh` editor, and git editor re-forced to vim on servers. The core
defaults to workstation behavior and every server fights it.

**F3a — Both real-flake blockers are removable; the fix for the harder one is a
one-liner.** Traced to the exact lock nodes:

- `obr` is `github:jwiegley/obr/fcbbce29`, but **its own committed `flake.lock`**
  pins `org2jsonl` to `file:///Users/johnw/src/org2jsonl` at rev `5ea75860`. The
  root repo's own `org2jsonl` is `github:jwiegley/org2jsonl` at a *different* rev,
  `59521f99`. `obr` is referenced in exactly one place —
  `config/packages.nix:37`, inside `userPackageInputAllowlist` — so it contributes
  a single user package and is low-risk to redirect.
  **Local fix:** `inputs.obr.inputs.org2jsonl.follows = "org2jsonl";` in the root
  `flake.nix`, which overrides `obr`'s lock entry with the github-pinned node.
  **Durable fix:** update `jwiegley/obr`'s own `flake.lock` upstream so every
  consumer stops inheriting a laptop-local path. Prefer the durable fix; the
  `follows` unblocks immediately without waiting on it.
  *Caveat from research:* Nix issue #14339 documents that *removing* a `follows`
  later does not respect the dependency's own lock, so this should be treated as a
  permanent declaration, not a temporary patch.
- `stock-trader` is a **root** input at `git+ssh://gitea/johnw/stock-trader.git`
  (LAN-only). It feeds only `overlays/30-stock-trader-mcp.nix`, which already
  tolerates absence via `inputs.stock-trader or null`. So it can move behind the
  optional/narrowed surface rather than being a hard blocker.

Neither blocker is architectural. This is the key feasibility precondition for
retiring `flake = false`, and it holds.

**F9 — The no-external-filesystem invariant test is one level too shallow.**
`bin/update-overlay-test.py:872` (`test_root_inputs_do_not_reference_external_filesystems`)
iterates only `lock["nodes"]["root"]["inputs"]`, so it validates *root* inputs
and never walks the transitive closure. The `obr` → `org2jsonl` →
`file:///Users/johnw/src/org2jsonl` leak from F3 therefore passes the test today.
Deepening this test to walk every node in `flake.lock` would both catch the
existing leak and turn "consumable as a real flake" into an enforced invariant —
this is the natural gate for the migration.

**F8 — Host-specific overlays stranded in a leaf repo.** `~/src/andoria/flake.nix`
carries ~250 lines of overlay fixes (git-branchless, libsecret, qdrant,
eternal-terminal, graphite-cli FHS, mitmproxy, optuna, pytest-postgresql,
mlx-speech). Most are **x86_64-linux** fixes, not andoria-specific, so any other
Linux host needing the same Python env would have to duplicate them.

**F10 — The core has a two-remote publish dependency, and consumers split across
both.** `nix-config` has two remotes: `origin` = `gitea@gitea:johnw/nix-config.git`
(LAN-only) and `github` = `git@github.com:jwiegley/nix-config.git`. Consumers do
not agree on which to use:

- `~/src/nixos` (vulcan) → `git+ssh://gitea/johnw/nix-config` (and
  `?dir=config/ai` likewise on gitea)
- `~/src/andoria` (4 work machines) → `github:jwiegley/nix-config?ref=main`
- `vps` → `github:jwiegley/nix-config?ref=main` (per project memory; the host's
  config lives only at `/etc/nixos` on the VPS and is not present locally)

So a core change is invisible to some hosts until pushed to **both** remotes, and
"which hosts have my change" depends on which remote received it. At session start
`main` was **8** commits ahead of both remotes; it reached **9** during this
session as the other autonomous agent committed. Every consumer is therefore
currently behind the core by 9 commits. This publish-fanout is a direct
contributor to the "confusion and difficulty" in the original request, and the
target design must state a single publish path.

**F11 — `vps` inventoried (correction: it is local, at `~/src/vps`).** The earlier
assumption that this configuration existed only at `/etc/nixos` on the host was
**wrong** — the user pointed to a local checkout at `~/src/vps` (~3,000 lines of
Nix, `nixosConfigurations.ovh-vps`, x86_64-linux). No SSH was needed. It is the
**third** independent consumer, and it repeats every defect already catalogued:

- **Dual fetch (F2), third instance.** `flake.nix:29-31`
  `nix-config = github:jwiegley/nix-config?ref=main` with `flake = false`, plus
  `flake.nix:19-21` `nix-config-ai = ...?dir=config/ai&ref=main` as a real flake.
- **Overlay internal-reach (F1), third instance.** `overlays/default.nix:17-18`
  cherry-picks from `30-user-scripts.nix` while manually re-injecting
  `00-lib.nix` into `prev` — the same implicit ordering contract vulcan
  reconstructs by hand. **All three consumers independently reproduce it.**
- **The `git-ai` stub problem (F6), stated outright in the source.**
  `flake.nix:41-44` keeps `git-ai` as a *full flake input* with the comment:
  "Kept as input so the shared johnw.nix config can import its HM module (the
  `programs.git-ai` options are defined unconditionally in the shared config).
  Disabled via mkForce in the VPS home-manager wrapper." So this host pays an
  entire flake input, and its `nixpkgs` follows, purely to satisfy an
  *unconditional* assignment for an *optional* feature it then force-disables.
  Vulcan solves the identical problem with a fake freeform option stub. **Two
  hosts, two different workarounds, one root cause.**
- **HM version skew (F6), third instance and the most expensive.** vps pins
  `home-manager/release-25.11` while the core targets master-only
  `programs.ssh.settings`, so it **vendors 920 lines of upstream home-manager
  verbatim** (`modules/home-manager/ssh-rfc42.nix`, a copy of master's
  `modules/programs/ssh.nix`) and swaps it in via `sharedModules` +
  `disabledModules`. Vulcan solved the same skew by writing a translation shim.
  The core's use of a master-only API is costing two hosts two separate,
  substantial workarounds.

**F12 — The real "closure" problem is inside the home-manager core, not in the
flake structure. This is the most important finding for the user's stated goal.**

The `flake.nix` / `flake-ai.nix` split exists because "we don't want to realize all
artifacts on all systems." That instinct identifies a **real** problem — but the
fix was applied at the wrong layer. Flake outputs are lazy (verified), so the
split buys nothing. Meanwhile the actual closure bloat lives in the shared HM
module, which is written for a fat workstation and unconditionally pulls
heavyweight dependencies that every lean host must surgically undo.

`~/src/vps/modules/users/home-manager/johnw.nix` contains **35 `lib.mkForce`
uses**, and most of its ~200 lines are closure surgery with the sizes named in its
own comments:

| Undone by the VPS | Cost cited |
|---|---|
| `programs.git-ai.enable` | ~2.3 GB Rust toolchain |
| `programs.vim.enable` | vim-full + GTK3, ~500 MB |
| `programs.password-store.enable` | ~432 MB |
| `programs.info.enable` | 123 MB |
| `xdg.configFile."aspell/config"` | ~110 MB |
| `programs.browserpass.enable`, `programs.gpg.enable` | pass ecosystem |
| `programs.git.package` → `gitMinimal` | avoids git-ai |

Worse, because `vars.gitPkg` is **string-interpolated into option values**, the VPS
must rewrite them one by one: **12 `programs.git.settings` overrides** (7 aliases,
2 `filter "media"` entries, credential helper, editor) and **5 `programs.zsh.shellAliases`**,
each replacing an embedded `gitPkg` store path with `gitMinimal`. Three
`sessionVariables` are blanked with the explicit reason that "their string
interpolations pull those packages into the closure."

Override-debt tally across all three consumers: **46 `mkForce` uses** (vps 35,
vulcan 6, andoria 5) **plus 920 vendored lines**. Nearly all of it exists to
subtract from a core that assumes a workstation.

> **Design consequence.** The core needs a *lean/full capability switch* — a
> profile dimension so servers opt *in* to heavyweight features rather than
> `mkForce`-ing them off one at a time — and heavyweight package references must
> stop being baked into interpolated strings, so that disabling a feature actually
> removes it instead of requiring per-alias surgery. This single change would
> delete most of the 46 overrides and is the highest-leverage item in the
> migration. There are also **three** package strategies in play today (full
> `packages.package-list` on darwin/vulcan/andoria, a curated list on vps), which
> the profile dimension should subsume.

vps also uses **sops-nix** (`.sops.yaml`, `secrets.yaml`, and a git credential
helper reading `/run/secrets/nix/git-credentials`), so sops-nix is already in use
on **both** NixOS hosts — reinforcing it as the continuity choice.

## F13 — URGENT: two hosts are armed for a hard eval failure on their next lock bump

Surfaced by the analysis workflow, then verified independently here. This is the
most actionable finding in the investigation and is worth acting on **before** any
migration.

Commit `a3cc3843` ("refactor(overlays): isolate platform and input ownership",
2026-07-26) changed several overlays from two-level `final: prev:` functions to
**three-level** `{ arg ? null, }: final: prev:` functions. Verified signatures at
HEAD:

| Overlay | Signature | Positional call |
|---|---|---|
| `30-misc-tools.nix` | `_final: prev:` | works |
| `30-markless.nix` | `_final: prev:` | works |
| `30-data-tools.nix` | `{ dirscan ? null, }: _final: prev:` | **breaks** |
| `30-text-tools.nix` | `{ org2tc ? null, }: _final: prev:` | **breaks** |
| `30-user-scripts.nix` | `{ scripts ? null, }: final: prev:` | **breaks** |
| `30-git-tools.nix` | `{ gitScripts ? null, }: _final: prev:` | **breaks** |

The three-level forms take a **strict** argument set with no `...`. Consumers that
call these files *positionally* pass `final` — the entire package set — where
`{ dirscan ? null, }` is expected, and Nix rejects it with
`function called with unexpected argument`.

**Armed call sites, verified:**

- **vulcan** — `~/src/nixos/overlays/default.nix` cherry-picks positionally at
  three now-incompatible sites: `30-data-tools.nix` (`tsvutils`),
  `30-text-tools.nix` (`filetags`), `30-user-scripts.nix` (`nix-scripts`). Its two
  calls into `30-misc-tools.nix` and `30-markless.nix` remain fine.
- **vps** — `~/src/vps/overlays/default.nix:17-18` cherry-picks
  `30-user-scripts.nix` positionally for `nix-scripts`, which *is* in johnw's
  package list on that host.

**Current lock positions (verified against this branch's history):**

| Consumer | Locked `nix-config` rev | Relative to `a3cc3843` | Status |
|---|---|---|---|
| vulcan | `a36d3f51` | **9 commits before** | not yet broken; **breaks on next bump** |
| vps | `1b71b192` | **19 commits before** | not yet broken; **breaks on next bump** |
| andoria | `269b518e` | **at/after** | **unaffected** |

**Why andoria is unaffected, and why that matters.** andoria is already *past* the
breaking commit yet works fine, because it does not cherry-pick overlay files at
all — it calls the maintained aggregator,
`import "${inputs.nix-config}/config/overlays.nix" { inherit inputs; aiOverlay = ...; }`,
which owns both the 00→30 ordering and the per-overlay argument sets
(`config/overlays.nix:21-51`). This is a natural experiment: **the consumer using
the supported entry point survived a breaking change to the internals; the two
consumers reaching past it are armed to fail.** It is the strongest available
evidence for the central thesis — that the fix is a stable public API, not more
careful path interpolation.

**Interim mitigation, independent of the migration:** point vulcan's and vps's
overlay cherry-picks at `config/overlays.nix` as andoria already does, or pass the
argument sets explicitly. Either removes the armed failure without waiting on any
architectural work.

Also verified: `nix-config` and `nix-config-ai` are currently locked to the **same**
revision in all three consumers, so the F2/D4 drift hazard is real but has **not**
manifested today.

## F14 — The work identity does not exist; work hosts author commits as the personal identity

Verified, and a live correctness issue rather than a stylistic one.

`config/vars.nix:15-18` binds identity as `let` constants
(`userName = "John Wiegley"`, `userEmail = "johnw@newartisans.com"`, plus
`master_key` and `signing_key`). `config/git.nix:141-142` then assigns
`name = userName; email = userEmail;` at **plain priority** — notable because the
same file deliberately uses `lib.mkDefault` two lines later for `editor`
(`:146`), and for `commit.gpgsign` (`:155`) and `credential.helper` (`:158`). So
the identity is *not* overridable by a consumer's `mkDefault`; only `mkForce`
would work.

A grep across all three consumer repositories found **no** override of `user.email`
or `user.name` for johnw/jwiegley anywhere. The only hits are unrelated: vulcan's
`radicale` service identity, and vps's separate `srashidi` user configuration
(which does parameterize its own email — demonstrating the pattern that johnw's
config lacks).

**Consequence:** the four work machines author git commits as
`John Wiegley <johnw@newartisans.com>`. `jwiegley@positron.ai` exists only as a
Fastmail *alias* in `config/email.nix:24`, not as a git identity. The fleet's second
identity is therefore unexpressible today, which is exactly the parameterization
gap R2 asks the design to close.

## Open questions requiring the user's decision

**Q1 — NFS `$HOME` branch (user's stated preference recorded, not yet ratified).**
When asked, the user selected **"Keep shared `$HOME`, state host-local"** but then
paused to clarify, so the selection is recorded as a *preference*, not approval.
It is also the correct call on the evidence: the four machines' generated
configuration is uniform by construction today, so this is where the fleet already
is, and it needs no change to how `$HOME` is mounted. The alternative —
host-local `$HOME` with NFS data mounted in — is more robust and is the only branch
permitting genuinely divergent per-host generated files, but requires sysadmin
changes on four work machines that may not be under the user's control. **Both
branches to be costed in the design; recommend the former; user ratifies at
review.**

**Q2 — Persistent host-local path for `XDG_STATE_HOME` on the four Ubuntu hosts.**
Must be persistent and **not** age-cleaned: not `/tmp`, and specifically **not
`/var/tmp`**, which systemd-tmpfiles reaps at 30 days, deleting gcroots. Asked
whether those machines have a conventional local scratch path; unanswered. Design
uses a clearly-marked placeholder until answered.

**Q3 — Trust domain for the four work machines.** The sops/age decryption identity
lives on the shared NFS home, so all four hosts currently share one identity. Fine
if they are one trust domain. Per-host keys would require host-local key files and
every secret encrypted to four recipients. Recorded, not assumed.

**Q4 — Integration of this branch.** `design/unified-fleet` is deliberately not
merged; another autonomous session is committing in `~/src/nix`. Merge timing and
method are the user's call.

**Q5 — Confirm `/nix` is host-local on the four Ubuntu machines.** The entire GC
analysis assumes `/nix/store` and `/nix/var/nix` are per-machine, which is normal
but unverified here. If `/nix` were itself NFS-shared, the analysis changes
materially. Cheap to check on each host.

**Operational warning to convey regardless of the above (see research doc):**
while the home-manager profile is shared over NFS, **do not run generation-expiry
commands on the four work machines** — `nix-collect-garbage -d`/`--delete-old`,
`home-manager expire-generations`, `nix profile wipe-history`,
`nix-env --delete-generations` — and check for any automatic GC timer with a
delete-old setting. Plain `nix-collect-garbage` and `nix store gc` are safe.

## How to resume

1. Re-read `doc/UNIFIED-CONFIG-WIGGUM-PLAN.md` and this file in full.
2. Re-run baseline: `nix flake check ./config/ai --all-systems --no-build`.
3. Check `doc/observations/` for actionable entries.
4. Continue from the first unchecked item under "Not started".

## Attempt counters

See the plan's counter table. All at 0 as of this update.
