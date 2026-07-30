# Fleet Programme — Verified Cross-Stream Findings

Durable record of couplings **between** the three concurrent work streams, each verified
in the repositories rather than inferred. Written 2026-07-27, before the master plan, so
these survive compaction and can be folded in regardless of what the synthesis finds
independently.

## The three streams

| Stream | Authority | Branch / location | State |
|---|---|---|---|
| **Architecture remediation** | GitHub issue #15 (exclusive, per `CLAUDE.md`) | `main` | checkpoint `e7c17869`; Phases 1–7; inventory 188/170/18 |
| **Pi fleet** | issue #15 + two handoff docs | `feat/pi-fleet` | 4 signed commits; WU5–WU9 + Phases F–I remain |
| **Fleet redesign** | `doc/FLEET-DESIGN-PLAN.md` | merged to `main` | 7 decisions resolved; 7 migration stages |

Sources: issue #15 body; `~/dl/nix-config-issue-15-remaining-scope-2026-07-27.md` (identical
to the `~/Downloads/` copy, `md5 23d13624ef217746412c3ef8f01de690` — `~/dl` is a
home-manager symlink into the store); `~/src/nix-pi-fleet/doc/PI-FLEET-WIGGUM-HANDOFF.md`;
`~/dl/pi-fleet-remaining-scope-2026-07-27.md`; `doc/FLEET-DESIGN-PLAN.md`.

---

## X1 — CRITICAL: `feat/pi-fleet` would resurrect reverted unsafe code

**Verified by git ancestry, not inference.**

```
a88a77ba  feat(sources): execute compound catalog updates      <- found UNSAFE by fess audit
a98385b9  Revert "feat(sources): execute compound catalog updates"   <- on main
```

- `a88a77ba` **is** an ancestor of `feat/pi-fleet` — the branch's recorded base.
- `a98385b9` is **not** an ancestor of `feat/pi-fleet`.

So the Pi fleet branch carries the compound-executor implementation that `main`
deliberately reverted. The status document is explicit: *"The `a88a77ba`/`a98385b9` pair is
intentional evidence. Do not resurrect the reverted implementation without addressing the
audit findings."* Merging `feat/pi-fleet` as-is would silently undo that revert.

**Consequences to own in an early issue:**

1. Rebase `feat/pi-fleet` onto post-revert `main` (currently `e7c17869`).
2. Re-verify all four commits against the new base — a gate that passed on the old base
   proves nothing on the new one.
3. Expect a textual conflict in `sources/ai.json` (see X3).
4. The audit findings behind the revert are now Phase 1.1's requirements, so the rebase must
   not reintroduce the pattern they reject: mutating catalog and lock files *while* computing
   dependent hashes.

`main` history is otherwise coherent — the revert landed cleanly after the design-doc
merges:

```
e7c17869 chore(inputs): update scripts source
a98385b9 Revert "feat(sources): execute compound catalog updates"
95ac688e docs(fleet): merge resolved design decisions
acd67222 docs(fleet): merge unified fleet configuration design
3a478b13 fix(darwin): scope Homebrew cleanup force
a88a77ba feat(sources): execute compound catalog updates
```

---

## X2 — Pi gallery: a contract coupling, not a textual conflict

Initially feared as a file collision; measurement shows otherwise, which materially
simplifies sequencing.

- **Issue #15 Phase 1.2** owns npm manifest normalization. Q1(a) makes one
  fail-closed executable contract under `packages/pi-gallery/` authoritative for
  both the Nix build and updater, with per-package locks at
  `packages/pi-gallery/locks/*.json`. Its nine records — `pi-artifacts`,
  `pi-dynamic-workflows`, `pi-hashline-edit-pro`, `pi-insights`, `pi-lens`,
  `pi-markdown-preview`, `pi-smart-fetch`, `pi-smart-web-search`, and
  `pi-subagents` — all live in `sources/pi.json`.
- **Pi fleet** does **not** touch `packages/pi-gallery/` at all. Its diff against its base
  touches only `config/ai/catalog.nix`, `config/ai/renderers/pi.nix`, and `sources/ai.json`.

They therefore share the pi-gallery **interface**, not its files. Pi fleet WU6 requires
"pass that exact derivation to `pi-gallery`" and WU8 asserts "Pi used by
`pi-gallery`" — both consume a contract Phase 1.2 is simultaneously reshaping.

**Resolution: order by contract, not by file.** Phase 1.2 should land its normalization
authority first, because it changes what "the manifest paired with a lock" *means*; Pi fleet
WU6/WU8 then assert identity against the settled contract. Doing WU6/WU8 first would assert
identity against a contract about to change, and the assertion would silently become
meaningless rather than fail.

---

## X3 — `sources/ai.json` is a genuine textual conflict surface

Pi fleet adds 16 lines to `sources/ai.json` (the `perplexity_mcp` record from `6effd650`),
while issue #15's WU4c catalog migration is actively rewriting `sources/*.json` — the very
work in flight on `main` right now. This is the concrete conflict the X1 rebase will hit,
and it is the reason the rebase is an owned work item rather than a formality.

---

## X4 — The rename must update Phase 1.6's allowlist

Issue #15 Phase 1.7 adds a production completeness gate rejecting undeclared Internet source
coordinates, and Phase 1.6 states the allowlist literally:

> repository-internal path inputs remain allowed (`path:./config/ai`, `path:./config/certs`)

The redesign renames `config/ai` → `config/fleet` (decision Q5a). So the rename must also
update that gate's allowlist, or the gate will reject the renamed path — or worse, silently
allow a stale one. **Any issue implementing the rename must list Phase 1.6/1.7 among the
references it updates.**

Two further alignments worth recording:

- Phase 1.6 keeps *"external filesystem references remain prohibited"*, which is exactly the
  invariant the transitive `obr` → `org2jsonl` `file://` leak violates (redesign finding
  F3a). The deepened lock-purity check and Phase 1.7's gate are the same concern approached
  from two directions and should be reconciled into one mechanism, not two.
- Phase 1.6 states *"private/network remotes such as Stock Trader remain valid Internet
  repository sources"*. So `git+ssh://gitea` is **valid**, and the redesign's recommendation
  to keep it out of the portable subflake stands on *remote fetchability*, not validity. The
  two positions are compatible; the reasoning must not be conflated.

---

## X5 — The hard sequencing constraint, and what it does not cover

The status document states: *"Do not begin WU6–WU10 until WU4c reaches a trustworthy
catalog-only zero-pending gate."* That is issue #15's **own** WU numbering (Phase 2 = WU6
wrappers … Phase 6 = WU10 native fleet verification).

Pi fleet uses a **different, colliding** WU numbering — its WU5–WU9 are theme parity,
canonical Pi package, generation transition, package ownership, and documentation. The
constraint does not literally name Pi fleet's units.

**Recommendation:** rename one scheme in the programme's issue titles so `WU6` is never
ambiguous, and state the real dependency in terms of artifacts rather than numbers — Pi fleet
WU6/WU8 depend on the pi-gallery contract (X2) and on `sources/ai.json` settling (X3), not on
issue #15's Phase 2 wrappers.

---

## X6 — Native-verification and activation overlap across all three streams

Three separate streams each demand native builds and then activation on the same hosts:

| Stream | Requirement |
|---|---|
| Issue #15 Phase 6 (WU10) | root/portable checks on all three systems; native Hera, Clio, Andoria/shared-work, Vulcan under `/etc/nixos/.nixos-build` locking, VPS. **QEMU not acceptable.** |
| Pi fleet Phase G | same three systems; then Phase H activation in order Clio → Hera → VPS → Vulcan → shared-work |
| Fleet redesign Stages 3–5 | vulcan, vps, then the four work machines as one atomic unit |

These must become **one** verification and activation programme, not three. Running them
separately would triple the activation risk, and the shared-work case cannot be done three
times independently.

### X6a — The work-fleet rollout procedure, corrected

**The config is shared; the four local Nix stores are not.** That asymmetry, not the profile
link, is what governs the rollout. It yields one hard invariant:

> **Every store path referenced by the shared `$HOME` symlinks must already exist in all four
> local stores before *any* machine writes those symlinks.**

Because `$HOME` is shared, the instant one machine activates, all four see the new symlinks.
Any machine whose local store lacks those paths has dangling links until it catches up. So a
naive "switch andoria-08, then the others in turn" opens a breakage window on three machines
lasting until the last switch completes.

**Copy-only is insufficient.** Verified against `~/src/andoria/flake.nix`: three of the four
activation steps have genuine per-host effects — `hostLocalXdgCache` (`:561`) runs
`mkdir -p /var/tmp/$USER/xdg-cache/nix`, creating a **host-local** directory that the shared
`~/.cache/nix` symlink then points at; `agentDeckHostLocalState` (`:528`) creates
`$HOME/.local/share/agent-deck-hosts/$(hostname -s)`, keyed per host; and
`checkNoLocalPasswdEntry` (`:468`) greps the *local* `/etc/passwd` and is meaningless unless
run per machine. Only `materializeHostSshConfig` (`:512`) is a write into shared `$HOME` that
one run satisfies. Copying store paths alone would leave three machines with a
`~/.cache/nix` symlink pointing at a directory that does not exist locally.

**So the two options combine rather than compete:** the copy is the *enabler*, and the
per-host switch is still *required*.

```bash
# 1. Realize the candidate ONCE, then pre-populate the other three stores.
#    Pull-based and parallel: no push credentials, no hub dependency, and
#    --substitute-on-destination lets each host take what it can from a cache
#    so only the delta crosses the network.
CAND=$(nix build --no-link --print-out-paths .#homeConfigurations."<attr>".activationPackage)
for h in andoria-t2 delphi-3bd4 gpu-server; do
  ssh "$h" nix copy --from ssh://andoria-08 --substitute-on-destination "$CAND" &
done; wait

# 2. Prove the closure is resident on all four BEFORE any activation.
for h in andoria-08 andoria-t2 delphi-3bd4 gpu-server; do
  ssh "$h" nix path-info -r "$CAND" >/dev/null && echo "$h OK"
done

# 3. Pin the PREVIOUS closure on all four so rollback survives GC.
#    Essential given the generation-deletion hazard: without a gcroot, the
#    rollback target can be collected out from under you.
for h in andoria-08 andoria-t2 delphi-3bd4 gpu-server; do
  ssh "$h" nix build --out-link /var/lib/jwiegley/rollback-prev "$PREV"
done

# 4. NOW switch, per machine, in order. Each switch is fast and local: no
#    downloads, and it cannot fail for missing paths. It exists to run the
#    per-host activation steps, not to realize the closure.
```

**Why this is both more efficient and more robust.** Efficient: the derivation is
byte-identical across all four, so the paths are the same and pre-population is pure
transfer with no rebuild; only one machine substitutes from the network. Robust: the
breakage window disappears entirely, because by the time the first symlink is written every
machine can already resolve it — and each subsequent switch is a local, no-download
operation that cannot fail partway for a missing path.

**This corrects an earlier over-broad claim in the design plan.** The four machines were
described as one indivisible unit whose rollback is group-level only. More precisely:

- **Store realization** is *not* atomic and should be deliberately staged — that is the
  whole point of pre-population.
- **The shared-`$HOME` symlink write** is effectively atomic, since one activation changes
  what all four see.
- **Rollback granularity depends on where the profile link lives**, which is currently
  **undetermined** and is one of the outstanding host-side checks
  (`readlink ~/.nix-profile; ls -la ~/.local/state/nix/profiles`). If the profile is shared
  (today's likely state, since nothing sets `xdg.stateHome` or `nix.useXdg` and
  `XDG_STATE_HOME` therefore defaults into the NFS home), rollback is **group-level**: one
  link move affects all four. Once decision Q2 moves state to `/var/lib/jwiegley`, each
  machine gains its own profile and generation series, and **state rollback becomes
  per-host** — a real improvement, and another reason to sequence the state relocation early.
- **Byte-identity remains load-bearing in both regimes**, because HM's `$HOME`-anchored
  links stay shared no matter where the state lives.

Known constraints, from the issue-15 status document: Clio connectivity has previously timed
out; Andoria's configured route previously attempted invalid x86-on-ARM QEMU; Vulcan's factory
route is disabled until its encrypted secret exists. **No activation authorization is
currently implied by any stream.**

---

## X7 — Blockers common to all streams

- **Independent `fess` after every subtask** is mandatory in both issue #15 and the Pi fleet
  plan. PAL currently has no credentials (`DIAL_API_KEY`, `OPENROUTER_API_KEY`,
  `CUSTOM_API_URL` all absent). Both plans treat this as a real blocker, so *unblocking the
  independent reviewer is itself a prerequisite work item*, not a side concern.
- **Bare root `nix fmt` is broken** — it invokes `nixfmt` with no paths and fails on empty
  stdin. Use `make format`. Any issue whose verification says `nix fmt` is wrong on its face.
- **Dual-remote drift.** During this session `main` reached 7 commits ahead of gitea and 19
  ahead of github, so vulcan (gitea) and the work fleet plus vps (github) were at different
  revisions of the core. Decision Q6 chose a scripted dual push; until that exists, every
  "advance the consumer to the tested revision" step must name **which remote**.

---

## X9 — RESOLVED and RE-SCOPED: vulcan is live-broken but still builds

Superseded X8 below. `~/src/nixos` is now synced to `37ef31aa` and clean, matching
vulcan's `/etc/nixos`. The sweep landed as `cbe33f25 docs: make comments and
documentation describe the running system`; the full delta from `334e8525` is 7 commits,
265 files, +6365/−1597.

**The armed breakage is no longer latent — vulcan's lock crossed the line.** Verified:
vulcan now locks `nix-config` and `nix-config-ai` at `03b5eecc`
("refactor(emacs): move package sources into catalog"), which is **29 commits *after***
`a3cc3843`. Previously it was `a36d3f51`, 9 commits *before*. The sweep's two
`flake.lock: Update` commits carried it across.

**And the positional cherry-picks were not fixed.** `overlays/default.nix` did change
(+24/−11) but the delta is **purely comment rewrites**; the positional calls survive at
`:307`, `:311`, `:314`.

**Measured on vulcan, read-only:**

| Attribute | Result |
|---|---|
| `tsvutils` | **FAIL** — `function 'anonymous lambda' called with unexpected argument 'system'` |
| `filetags` | **FAIL** — same |
| `nix-scripts` | **OK** — resolves (likely shadowed by the real `nix-config-ai` overlay output) |
| `nixosConfigurations.vulcan.config.system.build.toplevel.drvPath` | **EVALUATES OK** → `/nix/store/fw99q3zny1n0zvxbzkjbxy5d0dfqlk6i-nixos-system-vulcan-25.11.…drv` |

**Severity correction, in both directions.** My earlier prediction that vulcan "breaks on
its next lock bump" was directionally right, but the consequence is **narrower** than
stated: the bump has already happened, two overlay attributes are genuinely broken *now*,
yet **vulcan can still rebuild**, because nothing in its configuration consumes `tsvutils`
or `filetags` — a repo-wide grep finds no reference outside `overlays/default.nix` itself.
They are defined-but-unused, so laziness never forces them.

So the accurate statement is: **a live defect, not an outage.** It does not block rebuilds
today. It does mean (a) anything that starts consuming those attributes fails immediately,
and (b) because both vulcan inputs remain **floating with no `?rev`**
(`flake.nix:53-55`, `:116-118`), the surrounding state can shift under it at any
`nix flake update` with no warning.

**Revised priority.** Still first, but for a different reason: not "prevent an imminent
outage" but "stop a floating input from silently widening a known defect." The cheapest
mitigation that ships immediately — and needs no coordination with any other stream — is
**pinning vulcan's two inputs to an explicit `?rev`**. Routing the cherry-picks through
`config/overlays.nix` remains the real fix.

## X10 — The sweep is an asset: it documents which overrides are now inert

The sweep's value is not merely that it landed. `cbe33f25` systematically annotates
overrides with their *current* truth, and several annotations are directly actionable for
compatibility retirement (Epic 7) and the vulcan consumer migration:

- `check_systemd`: *"NOTE 2026-07-27: inert — nixos-25.11 renamed the top-level attribute
  to `nagiosPlugins.check_systemd`, which is what Nagios actually invokes, so the
  reload-notify patch is not in effect."* An override proven to have no effect — a
  zero-consumer surface, removable under the "prove zero usage" rule.
- `immich`: *"STATUS 2026-07-27: that condition is now MET — the locked nixpkgs-unstable
  (241313f4) evaluates immich to 3.0.3, so this dedicated pin is currently holding immich
  **down** at 3.0.1."* A pin that has inverted its purpose and is now a regression.
- `opower`: version note corrected from 0.18.0 to 0.18.6.
- Python: stable and unstable *"are no longer even on the same minor"* (3.13.12 vs 3.14.6).

**Consequence for the programme:** vulcan has effectively self-produced part of the
compatibility inventory that Epic 7 and issue #15's Phase 5 / WU9 require. Those
annotations should be harvested as inputs to the retirement decisions rather than
rediscovered. This also means the vulcan doc-sweep absorption issue is not a merge-conflict
chore — it is a source of evidence.

## X8 — SUPERSEDED by X9/X10: vulcan's documentation sweep as an unreadable stream

As of writing, `vulcan:/etc/nixos` is at `13f6d6b` — two commits ahead of `~/src/nixos`
(`334e8525`), both flake-lock updates — with **264 uncommitted modified files**: a large
documentation normalization sweep (`CLAUDE.md`, `README.md`, `SECURITY.md`, `certs/*.md`,
~40 `docs/*.md`, and `docs/superpowers/plans/*`). An agent session has been running there
roughly 23 hours.

Per the user's instruction, `~/src/nixos` is updated **only once vulcan goes quiet**; a
watcher polls for a stable tree with no agent process and no `/etc/nixos/.nixos-build` lock.
Until then vulcan's content is not readable, so the programme must be written to **absorb**
that work rather than assume its shape. Practically: no issue should quote vulcan's
documentation, and vulcan-only NixOS issues route to `jwiegley/nixos-config` where that work
will land.
