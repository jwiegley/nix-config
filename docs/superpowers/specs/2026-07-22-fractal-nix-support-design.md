# Nix-native Fractal support design

**Status:** Approved 2026-07-22

**Date:** 2026-07-22

**Repositories:** `/Users/johnw/src/ai-nix`, `/Users/johnw/src/nix`

## Purpose

Package and install Plasma AI's Fractal so that the existing `ai-nix` toolchain and the shared Nix host configuration can build and run it without `pip`, `pipx`, `uv tool install`, or an upstream installer. Preserve Fractal's complete runtime resources and its `plasma-wiki` companion while leaving agent-skill selection to the separate Nix-managed skills project.

A companion local change darkens Pi's pending-tool background to the same luminosity class as its completed-tool background.

## Scope

This work will:

- package `plasma-fractal` 1.0.0 and `plasma-wiki` 1.1.0 from immutable PyPI wheels;
- expose the `fractal` and `wiki` executables;
- provide the shell tools Fractal's bundled lifecycle scripts require;
- retain all bundled node seeds, scripts, schemas, TUI assets, and agent skills;
- expose stable, read-only Nix-store paths to the two top-level skill trees without selecting or installing them;
- add named `ai-nix` package outputs and include both packages in its default toolchain;
- install both packages through `/Users/johnw/src/nix/config/packages.nix` when the overlay makes them available;
- support `aarch64-darwin`, `aarch64-linux`, and `x86_64-linux`;
- add a Nix smoke test that exercises a real local Fractal initialization; and
- set Pi's live `toolPendingBg` value to the user-selected brown `#291B04`.

This work will not:

- invoke `fractal install` during build or activation;
- write to `~/.claude/skills` or `~/.agents/skills`;
- introduce a service, daemon, launch agent, or systemd unit;
- initialize Fractal in any existing repository;
- start an agent node or issue a provider request during tests;
- install Grok Build or Oh My Pi;
- add credentials or provider configuration;
- override Nixpkgs' existing `pkgs.fractal`, which is the GNOME Matrix client;
- update either flake lock; or
- rebuild, switch, or activate a host configuration.

The deferred skill-selection work is specified separately in `~/dl/fractal-nix-skills-management-handoff.md`.

## Upstream artifacts

### Plasma Wiki

- Distribution: `plasma-wiki`
- Version: `1.1.0`
- Artifact: `plasma_wiki-1.1.0-py3-none-any.whl`
- Raw SHA-256: `919e5fdd1ac1a312ba197b39c66f9483b2dcc92f755c263408791d90ab2c672b`
- Nix SRI hash: `sha256-kZ5f3RrBoxK6GXs5xm+Ug7LcyS91XCY0CHkdkKssZys=`
- Python requirement: `>=3.11,<3.15`
- Runtime dependency: `typer>=0.24,<1`
- Console script: `wiki`
- License: Apache-2.0

The wheel includes the complete `wiki/skills/wiki/` tree and its Git merge-index support script.

### Plasma Fractal

- Distribution: `plasma-fractal`
- Version: `1.0.0`
- Artifact: `plasma_fractal-1.0.0-py3-none-any.whl`
- Raw SHA-256: `44e7a4785526b2587bcb687f70e32feddd8208073c3c6c6227bccdbebee90e80`
- Nix SRI hash: `sha256-ROekeFUmslh7y2h/cOMv7d2CCAc8PGxiJ7zNvr7pDoA=`
- Python requirement: `>=3.12,<3.15`
- Runtime dependencies:
  - `plasma-wiki>=1,<2`
  - `rich>=15,<16`
  - `textual>=8,<9`
  - `typer>=0.24,<1`
- Console script: `fractal`
- License: Apache-2.0

The wheel contains the complete published package surface: lifecycle shell scripts, node templates, agent-specific configuration, iteration modes and steps, node skills, the SQLite schema, TUI stylesheet, TUI modules, and the top-level `fractal` skill.

The pinned `ai-nix` Nixpkgs revision already supplies compatible Python 3.14, Rich 15, Textual 8, Typer 0.25, SQLite 3.53, and tmux 3.7. Only the two Plasma distributions need new derivations.

## Package architecture

Create a focused `ai-nix` overlay rather than adding Fractal to the inference-oriented overlay or introducing a new flake input.

### `pkgs.plasma-wiki`

Use `python3Packages.buildPythonApplication` in wheel mode. Supply Typer from the pinned Python package set. Wrap `wiki` with Bash, coreutils, Git, GNU awk, and GNU grep: its configured Git merge driver executes a bundled shell script that calls those tools. Retain import checks and exercise `wiki --help` during installation.

Expose the complete skill tree at a stable package path:

```text
${pkgs.plasma-wiki}/share/skills/wiki
```

This path may be a symlink into the installed Python package; it must resolve entirely within the same immutable output and preserve every file beneath `wiki/skills/wiki/`.

### `pkgs.plasma-fractal`

Use `python3Packages.buildPythonApplication` in wheel mode. Its Python dependencies are `pkgs.plasma-wiki`, Rich, Textual, and Typer from the same Python package set.

Wrap `fractal` with a fallback runtime `PATH` containing:

- its own output's `bin` directory, because `start.sh` re-enters through the `fractal` command inside tmux;
- `plasma-wiki` for the `wiki` executable;
- Bash;
- coreutils, including GNU `sort -V` and `env`;
- Git;
- GNU awk, grep, and sed;
- `procps` for `ps`; and
- tmux.

The wrapper must not inject agent executables. Fractal selects an agent by command name, and the surrounding `ai-nix` toolchain already provides Claude Code, Codex, and OpenCode. Ambient agent selection remains visible and overridable. Selecting Grok Build or Oh My Pi without separately installing it should fail through Fractal's normal preflight.

Expose the complete top-level skill tree at:

```text
${pkgs.plasma-fractal}/share/skills/fractal
```

The package will retain `fractal install` as a user-invoked upstream command, but Nix will never invoke it. The stable share path is the future declarative interface.

### Name collision

Nixpkgs already defines `pkgs.fractal` as the GNOME Matrix client, version 14 at the pinned revision. The Plasma package therefore uses the unambiguous attribute `pkgs.plasma-fractal`. Its executable remains upstream's `fractal`.

No currently selected package in either toolchain contributes another `bin/fractal`, so adding `plasma-fractal` does not create a build-environment collision.

## `ai-nix` integration

Add the new overlay to the existing composed overlay list. Extend `aiPackagesFor` with optional inclusion of both `plasma-wiki` and `plasma-fractal`, preserving evaluation on platforms where a future dependency might mark itself unavailable.

Expose these named outputs for each supported system:

```text
packages.<system>.plasma-wiki
packages.<system>.plasma-fractal
```

The default `ai-nix-toolchain` will include both outputs. `nix build .#plasma-fractal` will build the application directly, while `nix develop` and `nix build .#default` will expose both `fractal` and `wiki`.

No new flake input is required, so `flake.lock` remains unchanged.

## `nix` integration

The shared Nix configuration already imports `inputs.ai-nix.overlays.default`. Add these optional packages to the AI and LLM section of `config/packages.nix`:

```nix
++ optPkg "plasma-wiki"
++ optPkg "plasma-fractal"
```

Explicitly selecting both packages makes `wiki` available to the user as well as to Fractal's wrapper. It also retains both outputs directly in the host generation rather than relying only on a runtime reference from the Fractal wrapper.

No Home Manager module, settings file, activation hook, or mutable initialization is needed. Fractal stores per-project state only after the user explicitly runs `fractal init`.

## Runtime behavior

A normal invocation follows this path:

1. The user runs `fractal` from the Nix profile or `ai-nix` development shell.
2. The Python wrapper supplies Fractal's module closure and fallback lifecycle tools.
3. `fractal init` resolves `wiki` from the wrapped `PATH` and creates project-local state only in the repository selected by the user.
4. `fractal node start` captures the current `PATH` into a tmux session. Consequently, the same Nix-provided `fractal`, `wiki`, shell tools, and ambient agent CLIs remain available inside the node loop.
5. Provider credentials remain inherited from the launching environment according to upstream behavior. Nix stores no secrets.

The package is usable with the Claude Code, Codex, and OpenCode executables already selected by these repositories. Packaging Fractal does not assert that every upstream backend is present.

## Failure behavior

- A missing agent executable remains a Fractal runtime preflight error.
- A missing provider credential remains an upstream agent/provider error.
- A malformed project or unsupported Git state remains a Fractal validation error.
- The wrapper closes only deterministic package-runtime gaps; it does not mask ambient configuration errors.
- Fixed-output hash drift fails the Nix build.
- Missing wheel resources fail installation checks.
- A future upstream executable or dependency change should fail the smoke test rather than trigger mutable installation or network access.

## Test strategy

Implementation follows test-driven development.

### Red phase

Add a Fractal smoke check to the flake before defining `pkgs.plasma-fractal`. Confirm that evaluation fails because the package does not yet exist. The failure must be attributable to the missing package, not malformed test syntax.

### Green phase

The package-level checks will verify:

- `import fractal` and `import wiki`;
- exact versions from `fractal --version` and package metadata;
- `fractal --help` and `wiki --help`;
- existence of every required resource class;
- complete stable skill directories, including each `SKILL.md` and `agents/openai.yaml` where published; and
- availability of the required wrapped lifecycle executables in a clean environment.

A Nix smoke derivation will create an isolated temporary Git repository, configure a local test identity, set `TMUX_TMPDIR` beneath the build temporary directory so it cannot observe or contend with a host tmux server, make a baseline commit, and run:

```text
fractal init --agent=codex
fractal node list
```

It will assert creation of the user-node configuration, central SQLite database, project wiki index, and repository-local exclusion block. It will not start tmux, launch Codex, contact a provider, or alter an existing checkout.

### Repository checks

For `ai-nix`:

- focused Fractal smoke derivation;
- named package build;
- default toolchain build;
- source parsing tests;
- formatting, Statix, deadnix, and warning-free checks;
- flake evaluation for `aarch64-darwin`, `aarch64-linux`, and `x86_64-linux`; and
- `git diff --check`.

For `nix`:

- focused package-list evaluation on the current host;
- existing repository formatting, linting, and evaluation checks appropriate to the two-line package selection change; and
- `git diff --check`.

No host switch, Home Manager activation, remote deployment, or provider-backed Fractal run is part of verification.

## Deferred Nix-managed skill deployment

Option B is intentionally not implemented here. The packages expose immutable skill trees, but selection and target projection belong to the Nix-managed agent-configuration infrastructure already under development.

The separate handoff report specifies:

- exact source paths;
- complete-tree preservation;
- client selection policy;
- collision and ownership rules;
- migration from mutable/plugin-installed copies;
- activation ordering; and
- acceptance tests.

This separation prevents `fractal install`, Home Manager files, and the catalog-based deployment system from competing for the same destinations.

## Pi pending-tool color

Change the live custom theme at:

```text
/Users/johnw/.pi/agent/themes/dark-tool-backgrounds.json
```

The final user-selected value is:

```text
#291B04
```

The completed-tool background remains `#180526`. Pi themes hot-reload, although `/reload` may still be used to force resource refresh. Validation parses the JSON, verifies the exact two values, and confirms that all other theme fields remain unchanged.

## Deliverables

### `ai-nix`

- Fractal overlay with the two derivations;
- overlay registration;
- named and default package exposure;
- Fractal smoke check;
- README package inventory update; and
- this design specification.

### `nix`

- optional installation of `plasma-wiki` and `plasma-fractal` in `config/packages.nix`.

### Outside the repositories

- `~/dl/fractal-nix-skills-management-handoff.md`;
- updated live Pi theme value; and
- no generated dependency state or mutable Fractal installation.

## Acceptance criteria

The work is complete when all of the following hold:

1. `nix build .#plasma-fractal` succeeds in `ai-nix` on the current host.
2. The default `ai-nix` toolchain exposes working `fractal` and `wiki` commands.
3. The clean-environment smoke test initializes and inspects a temporary Fractal without network or agent execution.
4. All three declared systems evaluate both named packages.
5. `nix` selects both packages through its existing optional-package mechanism.
6. No skill destination, credential file, Fractal project, lock file, or host generation is mutated.
7. The Option B handoff report is complete and independently actionable by the Nix-managed skills session.
8. Pi's pending tool background is exactly `#291B04`, its completed background remains `#180526`, and the custom theme remains otherwise unchanged.
9. Relevant checks pass without warnings, and final diffs contain no unrelated changes.
