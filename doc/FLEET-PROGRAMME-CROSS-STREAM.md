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

- **Issue #15 Phase 1.2** owns npm manifest normalization. The policy is inline at
  `packages/pi-gallery/default.nix:87-97` (`del(.devDependencies)`, conditional
  `del(.peerDependencies, .peerDependenciesMeta)` under `dropPeerMetadata`, then pairing
  `${lockFile}`), with per-package locks at `packages/pi-gallery/locks/*.json`. Its six named
  records — `pi-artifacts`, `pi-dynamic-workflows`, `pi-hashline-edit-pro`, `pi-insights`,
  `pi-lens`, `pi-web-access` — all live in `sources/pi.json`.
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
separately would triple the activation risk on hosts that share a profile link, and the
shared-work case cannot be done three times independently — it has one profile link for four
machines.

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

## X8 — Vulcan's documentation sweep is a fourth, unreadable stream

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
