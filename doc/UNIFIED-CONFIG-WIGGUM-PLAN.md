# Unified Fleet Configuration — Frozen Plan and Definition of Done

**Created:** 2026-07-27
**Status:** FROZEN. This file is read-only with respect to lowering the bar.
**Scope:** Research and *design* only. No migration is executed under this plan.

## The ask

Devise a unified, harmonious architecture replacing the current ad-hoc split
across three repositories (`~/src/nix`, `~/src/nixos`, `~/src/andoria`), giving
a single "master core" plus declarative variants per host and per environment,
while preserving correctness, security, and reliability.

## Fleet (authoritative)

| Machine | OS | Activation | Arch | Role | Config dir |
|---|---|---|---|---|---|
| `hera` | macOS | nix-darwin + HM | aarch64 | Personal, Work (full) | `~/src/nix` |
| `clio` | macOS | nix-darwin + HM | aarch64 | Personal, Work (lite) | `~/src/nix` |
| `vulcan` | NixOS | NixOS + HM | aarch64 | Personal (home server) | `/etc/nixos` |
| `vps` | NixOS | NixOS + HM | amd64 | Personal | `/etc/nixos` |
| `andoria-08` | Ubuntu | standalone HM | amd64 | Work | `~/.config/home-manager` |
| `andoria-t2` | Ubuntu | standalone HM | amd64 | Work | `~/.config/home-manager` |
| `delphi-3bd4` | Ubuntu | standalone HM | amd64 | Work | `~/.config/home-manager` |
| `gpu-server` | Ubuntu | standalone HM | amd64 | Work | `~/.config/home-manager` |

Constraints stated by the user, treated as requirements:

- **R1.** Vulcan's system configuration stays out of `~/src/nix`. It is large and
  single-environment. Only its *home-manager core* is shared.
- **R2.** The home-manager core is shared by every host, parameterized by
  environment: username, email, GPG/SSH identity, signing policy.
- **R3.** Full HM configuration realizes only on `clio` and `hera`.
- **R4.** The nix-darwin core is shared by `clio` and `hera`; full only on `hera`.
- **R5.** The four work machines are configured near-identically but **share one
  `$HOME` over NFS**, so per-host paths must diverge to avoid collision.
- **R6.** Remote hosts must not be forced to fetch or realize artifacts they do
  not need.

## Definition of Done

Exit only when all hold, each with cited evidence rather than assertion:

1. **DoD-1 — Current-state inventory.** Every cross-repository coupling between
   the three repos is enumerated with `file:line` evidence: module imports,
   hand-called internal functions, cherry-picked overlay attributes, duplicated
   inputs, and implicit ordering contracts.
2. **DoD-2 — Root-cause analysis.** Each identified defect is traced to a root
   cause at the narrowest shared seam, distinguishing *actual* technical
   constraints from *believed* ones. In particular, the claim that the
   `flake.nix` / `flake-ai.nix` split is required for closure reduction must be
   confirmed or refuted with a concrete mechanism.
3. **DoD-3 — External research.** Community best practices researched via
   `web-searcher` across: monorepo vs multi-repo, evaluation/closure isolation,
   `flake-parts` vs `snowfall-lib` vs `flakelight` vs hand-rolled, tri-context HM
   module sharing, declarative host variance, NFS-shared-`$HOME` idioms, and
   secrets across mixed activation contexts. Findings cited with URLs and dates,
   distinguishing consensus from single-author opinion.
4. **DoD-4 — Multi-model consensus.** The design is reviewed via PAL with
   `gpt-5.5-pro` and `gemini-3.1-pro-preview`. Dissent is recorded, not hidden.
5. **DoD-5 — Design document.** A written architecture covering: repository
   topology, the core/variant layering model, the public module API, the host
   metadata schema, per-host path derivation under shared `$HOME`, secrets
   handling per activation context, lock and version-skew policy, and the
   security invariants preserved.
6. **DoD-6 — Migration plan.** A staged, individually-verifiable sequence with
   an explicit rollback for each stage, and a per-stage verification command.
   No stage may require a flag-day cutover across hosts.
7. **DoD-7 — Baseline integrity.** `nix flake check ./config/ai
   --all-systems --no-build` and `python3 -m unittest bin/update-overlay-test.py`
   pass, and `nix fmt` is clean. Passing output shown, not claimed.
8. **DoD-8 — Audited.** The final commit passes an independent `fess` audit.
9. **DoD-9 — Observations drained.** No actionable `doc/observations/` entry
   outstanding at the last cleanup cycle.

## Explicitly out of scope

- Executing the migration. This plan produces the design and the staged plan.
- Any system or Home Manager activation, on any host.
- Any push, force-push, or history rewrite.
- Restructuring Vulcan's system configuration (R1).

## Stop-and-escalate conditions

- Ambiguity about a requirement that changes the design's shape.
- PAL consensus unreachable after two rounds.
- Any action that would activate, push, or rewrite history.
- The same gate failing 3 times without intervening progress.

## Attempt counters

| Gate | Attempts | Status |
|---|---|---|
| `nix flake check ./config/ai` | 0 | not yet run |
| `nix fmt` clean | 0 | not yet run |
| PAL consensus | 0 | not yet run |
