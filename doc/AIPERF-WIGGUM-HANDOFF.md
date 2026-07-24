# AIPerf Wiggum Handoff

Updated: 2026-07-14

## Completion contract

- Frozen target and done criteria: `doc/AIPERF-WIGGUM-PLAN.md`.
- AIPerf must land as commits separate from the completed Pi work in both
  repositories.
- Only AIPerf-related audit findings are in scope for this work.

## Completed evidence

- The canonical upstream is `ai-dynamo/aiperf`; the current stable release is
  0.11.0 and its console executable is `aiperf`. Upstream requires Python
  `>=3.10,<3.14` and intentionally supports `aarch64-darwin`, although its full
  integration CI is Linux-only.
- Neither the pinned `llm-agents.nix` input nor pinned `nixpkgs` exports a
  suitable AIPerf package, so a local `ai-nix` derivation is required.
- `ai-nix` commit `1427d282054b9e118dfbf5a70da74c746ac5d962`
  packages AIPerf with `python313Packages`, adds it to the aggregate, and
  documents the inventory. Its diff is limited to `README.md`, `flake.nix`,
  and `overlays/30-ai-llm.nix`; it is published on `main`.
- The official AIPerf 0.11.0 wheel uses
  `sha256-Fjjyk9BdQmFCXKiBQCoQAxNrbecrrHKpUEKPMrbhkmA=`. Local compatibility
  packages use `crick` 0.0.8 with
  `sha256-lzuDFf3XK961/fTWsvREdT/A69Y4Dzj44ROPj/h5fZk=` and `kaleido` 1.2.0
  with `sha256-wn7YK1Hfa5I9DmVv6sIhNDoNvNL7m8fmsduX9h6aFRM=`.
- Dependency relaxations are explicit for `aiofiles`, `aiohttp`, `dash`,
  `jmespath`, `pandas`, `pillow`, `plotly`, `prometheus-client`, `psutil`,
  `pyzmq`, `rich`, `ruamel-yaml`, and `textual`. `async-timeout` is correctly
  omitted on Python 3.13, and Uvicorn's standard optional dependencies are
  included.
- The local Seaborn dependency excludes only the Darwin-specific
  `test_ticklabels_overlap` failure. Its suite otherwise reported 2,274
  passed, 59 skipped, and 5 expected failures.
- Hera's package set exposed nondeterministic timeouts in Cyclopts' interactive
  Zsh prompt harness. A private Darwin-only override removes Zsh from that one
  cross-shell behavior matrix while retaining its 36 Bash/Fish cases and the
  complete static Zsh suite. Cyclopts passed with 2,510 tests in Hera's pinned
  nixpkgs context and 2,508 tests in the direct `ai-nix` context; their
  inherited deselection counts differ by two.
- The wrapper supplies `ffmpeg-headless` on `PATH`. Kaleido static-image export
  still expects an external Chrome or Chromium installation; Hera already has
  Chrome, and the browser is intentionally absent from this package closure.
- The final direct `ai-nix` aggregate selects
  `/nix/store/pfpfm8kfyfzpf58032qs6shqg0c6fqm7-aiperf-0.11.0.drv`, producing
  `/nix/store/gnv264ws5615pqigakwbz90xgdl8iqrs-aiperf-0.11.0`. The Hera parent
  selects `/nix/store/byjfc7sk0hyvyi8jw66mwzck33lmgp9h-aiperf-0.11.0.drv`,
  producing `/nix/store/5h1qqv5g8h12sxz27vcdzh7napv2zrlp-aiperf-0.11.0`.
  Both builds' install checks passed, including exact version 0.11.0, help
  markers, `plugins --all --validate` reporting `All checks passed`, profile
  help, configuration list/init/minimal validation, TDigest behavior, and the
  Python import check.
- Direct isolated, offline smokes against that exact output passed. The
  `ai-nix-toolchain` derivation directly references the AIPerf derivation.
- The final `ai-nix` format, lint, source-test, and flake-evaluation gates
  passed. The commit's normal hooks also passed format, lint, coverage, and
  profile checks.
- An independent implementation review found no required AIPerf corrections.
  A later fess audit caught and corrected one inaccurate Kaleido test comment,
  then passed the final package and Cyclopts override with no further required
  correction.
- Hera's complete Darwin configuration built and switched successfully as
  generation 860. Its active system is
  `/nix/store/yi7aqxk7lxs9hxrmma5f1pkd22w20paq-darwin-system-26.11.d5bd9cd`.
  `/etc/profiles/per-user/johnw/bin/aiperf` resolves to the parent output above;
  isolated offline version, help, plugin, profile, configuration, FFmpeg
  closure, and Chrome-presence checks passed.
- The published AIPerf and Pi closures were copied to Clio without building
  there. On that independent Darwin arm64 host, Pi 0.80.6 passed isolated
  offline version/help/model-list checks and AIPerf 0.11.0 passed isolated
  offline version/help/plugin/profile/configuration checks.
- The parent lock pins the published `ai-nix` commit with nar hash
  `sha256-zLXzxm73uTiMzqXch1iBPf4xKtTD+rYaqx1VDSUZBqI=`. With local overrides
  disabled, both the AIPerf package and complete Hera system realizations
  returned successfully and resolved to the same active package and system
  outputs.

## Pending work

1. Run an independent AIPerf-only fess audit of this four-path parent unit and
   address only related findings.
2. Push normally, verify both remote `main` refs, and recheck every frozen done
   criterion.

## Repository and tooling state

- The completed Pi commits are already published and remain distinct from this
  AIPerf work.
- A full `ai-nix` aggregate-output attempt is not current AIPerf evidence: it
  was stopped after exposing a large unrelated rebuild set. The exact
  aggregate-selected AIPerf derivation built successfully. A pre-existing
  `cohere-melody` native-module import failure through `omlx` is outside this
  task and must not be repaired here.
- Unrelated working-tree changes observed earlier were left to their owning
  agent. This parent commit is limited to the four AIPerf files.

## Stop-and-escalate counters

- Repeated failing signature: none (0/3).
- Unresolved destructive or intent-sensitive action: none.
