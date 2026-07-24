# AIPerf Wiggum Plan

Status: frozen on 2026-07-14. These completion criteria may be clarified, but
not reduced.

## Target

Make the AIPerf inference-benchmarking CLI from
<https://github.com/ai-dynamo/aiperf> available and usable on Hera through the
existing declarative Nix configuration. Prefer an established upstream Nix
package if one exists; otherwise package the current stable upstream release
in `ai-nix` without changing its command, plugin, profile, or configuration
semantics. Upstream AIPerf is the source of truth; no separate implementation
is a parity target.

## Done criteria

1. Confirm AIPerf's canonical upstream identity, stable version, executable,
   Python constraint, supported platform, and runtime requirements from
   current authoritative sources.
2. Confirm that neither the pinned `llm-agents.nix` input nor pinned `nixpkgs`
   provides a suitable AIPerf package. Package AIPerf 0.11.0 in `ai-nix` with
   Python 3.13, satisfying upstream's `>=3.10,<3.14` constraint.
3. Supply the complete unconditional dependency closure, including compatible
   local `crick` and `kaleido` packages where the pinned Python set is missing
   or too old. Keep dependency relaxations and test overrides explicit,
   minimal, and justified, and expose support for `aarch64-darwin`.
4. Put FFmpeg on AIPerf's wrapped `PATH`, preserve upstream plugin discovery,
   and document that Kaleido static-image export still requires an external
   Chrome or Chromium installation rather than adding a browser to the
   package closure.
5. Pass isolated, offline package checks for import, exact version, top-level
   help, plugin validation, profile help, configuration listing and
   initialization, minimal configuration validation, and `crick` TDigest
   behavior.
6. Include AIPerf in the `ai-nix` aggregate toolchain and document that
   inventory. Pass the complete relevant `ai-nix` format, lint, source-test,
   and flake-evaluation gates; build the exact aggregate-selected AIPerf
   derivation and prove aggregate membership.
7. Include AIPerf in the shared managed-host package list, build and switch
   Hera's complete Darwin configuration, then prove the activated `aiperf` is
   the Nix-managed executable and passes isolated offline version, plugin,
   profile, and configuration smokes. Copy the proven closure to Clio without
   building there and repeat the isolated execution proof on that host before
   declaring completion.
8. Keep AIPerf commits separate from the Pi commits in both repositories,
   audit each logical change independently, and address only observations
   caused by these AIPerf changes. After Hera verification, publish `ai-nix`,
   refresh the parent lock, rebuild without the local override, commit and push
   the parent change normally, and verify both remote `main` refs. Never
   rewrite shared history or force-push.

## Explicit non-goals

- Do not configure benchmark endpoints, models, credentials, datasets, or
  distributed workers without a separate request.
- Do not add Chrome or Chromium to AIPerf's wrapper closure; Hera already
  manages a browser separately.
- Do not fix unrelated `cohere-melody`/`omlx` aggregate failures or inspect,
  modify, stage, or commit working-tree changes owned by another agent.
