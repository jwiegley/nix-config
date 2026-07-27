# Architecture Remediation Wiggum Plan

Status: FROZEN on 2026-07-26. Criteria may be clarified but never reduced.

## Authority

- Audit: `/Users/johnw/doc/obsidian/Nix Configuration Architecture and Maintainability Audit 2026-07-26.md`
- Repository baseline: `a36d3f51d92158e4e055e3baca85044f575e25a6`
- PAL: explicitly waived by the user for this effort.
- Saved read-only planning workflow: `nix-architecture-remediation`.

## Definition of Done

All conditions require fresh evidence:

1. Every audit finding P0-1 through P2-22 has one implemented or evidence-backed retained disposition in the coverage matrix.
2. Package updates have one discoverable, complete, atomic authority covering overlays, Pi gallery, Anvil, agent resources, fixed input URLs, locks, and synchronized tests.
3. Darwin-only pins/fixes are inactive on Linux, proven by derivation parity checks.
4. Overlay ordering and input provenance are explicit; `pkgs.inputs` is not a configuration bus.
5. User and feature package ownership is explicit; adding a flake input cannot silently install software.
6. Root and portable AI input membership, package groups, and Pi gallery membership each have one source of truth while retaining separate locks.
7. Root README/CLAUDE and one current architecture/work authority make repository purpose, hosts, commands, authorization, and deployment ownership discoverable.
8. Concrete Claude/Codex/Droid wrapper implementations and Anvil runtime programs have client/language-local ownership without adding speculative public interfaces.
9. Quality policy has one authority; names represent real evidence; CI executes the documented contract subset; long resilience soaks are explicit scheduled/release gates.
10. Home Manager, model-sync, package-selection, wrapper, and Anvil checks have focused cache/failure boundaries without weakened behavioral, security, concurrency, or lifecycle coverage.
11. Verified dead/superseded surfaces are removed. Conditional compatibility surfaces are removed only after external-consumer evidence proves them unused; otherwise their retained contract is documented and tested.
12. Root checks pass on aarch64-darwin, aarch64-linux, and x86_64-linux. Native fleet builds pass for Hera, Clio, Andoria shared-work, and Vulcan.
13. Authorized activations are idempotent and preserve sessions/state. No push or destructive history rewrite occurs without the standing authorization applicable at that step.
14. Every work commit passes an independent fess audit; partner observations are drained or explicitly non-blocking; final branch is clean and locally current with base.
15. A completion report is written to `~/doc/obsidian` with commit, build, test, deployment, coverage, retained-risk, and rollback evidence.

## Guardrails

- Use the working tree's direnv; never `nix develop` or ad-hoc installs.
- Coordinator alone edits canonical files and runs git.
- Use Anvil by default; check modified buffers before edit batches and commits.
- Preserve unrelated work and mutable runtime state.
- Signed commits only. One logical work unit per commit; small coupled units may share a commit.
- Never weaken tests, suppress a new failure merely to pass, or lower this plan.
- Repeated unchanged failure: root-cause after attempt 2, escalate after attempt 3.
- Rebase/restack locally only; force-push/shared-history rewrite is human-gated.

## Baseline gate

```bash
python3 -m unittest -v bin/update-overlay-test.py
nix flake check ./config/ai --all-systems --no-build
nix build --no-link \
  .#checks.aarch64-darwin.agent-resources \
  .#checks.aarch64-darwin.agent-wrappers \
  .#checks.aarch64-darwin.ai-home-manager-contract \
  .#checks.aarch64-darwin.pi-gallery
./build system
```

## Work units

### WU0 — Freeze state and baseline

Write plan/handoff/journal; inventory partner observations; run baseline gate; record current fleet revisions and generation links without exposing secrets.

### WU1 — Navigation, authority, and proven deletions

Primary findings: P0-3, P2-15, P2-16, P2-18.

- Add authoritative root README and CLAUDE; one current architecture index and host matrix.
- Establish one current-work authority; archive/delete superseded capsules after migrating live decisions.
- Compose duplicated prompts instead of embedding copies.
- Remove verified orphan/shallow files, duplicate license, stale CI references, and empty Beads placeholders.
- Make default `make` non-mutating and commands self-describing.

### WU2 — Atomic update authority

Primary finding: P0-1. Secondary: P1-7, P1-8, P1-16.

- Build one Nix-evaluable update manifest and complete inventory command.
- Cover overlay packages, Pi gallery, Anvil, agent resources, fixed-revision inputs, dual locks, package locks, projections, adapter ledgers, and tests.
- Plan all replacements before one atomic write transaction; preserve tree on any failure.
- Make one update command own both locks and remote deployment invoke maintained wrappers.

### WU3 — Platform and overlay isolation

Primary findings: P0-2, P1-5, P1-6.

- Darwin-gate pins and fixes; separate cross-platform package definitions.
- Replace directory-discovered ordering with one explicit ordered overlay manifest.
- Replace `pkgs.inputs` publication/restoration with explicit input factories and required-input arguments.
- Add Linux parity and duplicate-input provenance tests.

### WU4 — Package and gallery ownership

Primary findings: P1-4, P1-8, P1-14, P1-16. Secondary: P2-18.

- Replace input denylist/package-shape discovery with explicit user-package allowlist.
- Move Hera/feature-owned packages to owning modules.
- Create one Pi gallery member manifest deriving tarballs, derivations, roots, projection, generated registration, passthru, exports, and public versions.
- Move independent derivations under `packages/`; leave overlays as exposure/override layers.
- Remove the pass-through path registry and resource overlay where deletion tests hold.

### WU5 — Host, role, and operational ownership

Primary findings: P1-15, P2-17.

- Make host modules real owners or delete inert stubs.
- Replace username role inference with explicit home role/class.
- Centralize host-to-config/output routing for Hera, Clio, Vulcan, VPS, and Home Manager hosts.
- Split workspace refresh from repository deployment; restore explicit verification.
- Collapse repeated project/format traversal into data tables and parameterized runners.

### WU6 — Portable AI boundary and wrappers

Primary findings: P1-7, P1-9, P1-17.

- Centralize portable input declarations/membership while retaining dual locks.
- Move root/portable coherence and host checks to root; give portable checks an explicit fileset and target.
- Keep `patchAgentPackage` only as a small dispatcher; move concrete client implementations and version contracts to client-owned modules.
- Preserve public compatibility only where consumer evidence proves it live.

### WU7 — Anvil implementation locality

Primary finding: P1-13. Secondary: test recommendations.

- Move six named embedded Python/Elisp programs to language-native files loaded by the package composition root.
- Preserve timeoutPolicy and workerSpecs as single test-visible policy owners.
- No behavioral redesign in the extraction commit.

### WU8 — Quality and contract architecture

Primary findings: P1-10, P1-11, P1-12.

- One quality authority delegated to by Make, lefthook, CI, and flake apps.
- Remove fake evidence aliases after consumer audit.
- Split catalog/renderers, Home integration, model-sync, and package-selection checks.
- Split Anvil focused/unit, protocol, lifecycle, and scheduled soak gates; preserve all valuable behavior.
- Wire existing focused extension tests and executed updater transaction tests.
- Bound diagnostics and report structural diffs.

### WU9 — Conditional compatibility retirement

Primary findings: P2-19 and remaining conditional P2 dispositions.

- Audit every maintained consumer/worktree for `flake-ai.nix`, global Anvil mode, Node-RED assets, compatibility aliases, and historical authority links.
- Delete only zero-consumer surfaces; otherwise document owner, reason, and retirement trigger.

### WU10 — Fleet parity and completion

- Run full root and portable checks on all supported systems.
- Native build Hera, Clio, Andoria shared-work, and Vulcan.
- Activate only under standing authorization and platform lock rules; run unchanged second activation.
- Run final fess, partner cleanup, local rebase/restack, clean-tree check, trace matrix, and Obsidian completion report.

## Coverage matrix

| Findings | Primary unit |
|---|---|
| P0-1 | WU2 |
| P0-2 | WU3 |
| P0-3 | WU1 |
| P1-4 | WU4 |
| P1-5 | WU3 |
| P1-6 | WU3 |
| P1-7 | WU6 |
| P1-8 | WU4 |
| P1-9 | WU6 |
| P1-10 | WU8 |
| P1-11 | WU8 |
| P1-12 | WU8 |
| P1-13 | WU7 |
| P1-14 | WU4 |
| P1-15 | WU5 |
| P1-16 | WU4 |
| P1-17 | WU6 |
| P2-15 | WU1 |
| P2-16 | WU1 |
| P2-17 | WU5 |
| P2-18 | WU1/WU4 |
| P2-19 | WU9 |

## Deployment matrix

| Consumer | Build authority | Activation authority | Required evidence |
|---|---|---|---|
| Hera | root `nix-config` | nix-darwin | clean commit, system build, switch, second-switch generation parity |
| Clio | root `nix-config` on Clio | nix-darwin | native build, switch, parity; unreachable is blocker |
| Andoria/Delphi/GPU | each `~/.config/home-manager` | standalone Home Manager | merged lock, native build, switch twice, session preservation |
| Vulcan | `/etc/nixos` | NixOS | `.nixos-build` lock, native build, switch, service health, second switch |

## Per-unit loop

1. Re-read handoff and confirm baseline/attempt counter.
2. Anvil modified-buffer/status checkpoint.
3. Implement one unit; run focused tests and full impacted gate.
4. Review diff; create signed atomic commit.
5. Independent fess audit; verify and fix real findings.
6. Drain `doc/observations/` through partner cleanup.
7. Rebase/restack locally before the next independent unit.
8. Update handoff and append journal learning.
