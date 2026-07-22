# ai-nix

I wanted one Nix shell that I could enter on a fresh machine and have the AI
tools I reach for already there: agent CLIs, local model utilities, MCP
servers, and a few bits of glue that make those tools nicer to use together.
That's what this flake is for.

Run:

```sh
nix develop
```

The default shell includes the toolchain itself, plus the development tools
needed to check this repository: `nixfmt`, `statix`, `deadnix`, `shellcheck`,
`shfmt`, `hyperfine`, `jq`, and `lefthook`.

The shell currently brings in:

- agent CLIs from `llm-agents.nix`: `claude`, `ccusage`, `codex`, `droid`,
  `gemini`, `git-surgeon`, `mcporter`, `opencode`, and `pi`
- `agent-deck`, a tmux-based TUI that runs and switches between many concurrent
  agent sessions (Claude, Codex, Gemini, OpenCode, and more) from one terminal.
  It requires `tmux` at runtime; the package carries `tmux` and `git` only as a
  fallback, so your own `tmux`/`git` still win and attaching to a session
  yourself (`tmux attach`) uses the `tmux` on your PATH
- Plasma Fractal and its `wiki` companion, providing hierarchical agent loops
  in Git worktrees and tmux. The package includes complete upstream `fractal`
  and `wiki` skill trees but does not install them into agent homes; skill
  selection is owned by the separate Nix-managed agent configuration
- `git-ai` in its minimal form, so `git-ai` is available without replacing
  `git`
- LazyCodex, via the pinned `lazycodex-ai` installer CLI
- Simon Willison's `llm` CLI, with the MLX plugin on Apple Silicon
- local inference and model tools: `llama.cpp`, `llama-swap`, `gguf-tools`,
  `hfdownloader`, `aiperf`, `guidellm`, `qdrant`, and `qdrant-web-ui`
- Apple Silicon MLX tools when available: `mlx-lm`, `mtplx`, `omlx`, and
  `vllm-mlx`
- MCP servers and agent helpers: PAL, Sequential Thinking, Context7,
  Playwright, GitHub, Context Hub, Rust docs, Drafts on macOS, and Sherlock
- Claude transcript and configuration tools: `claude-vault`, `claude-replay`,
  and `agnix`

The shell sets only non-secret runtime defaults: updater suppression, Hugging
Face transfer support, and CA bundle variables. It doesn't include API keys,
private paths, hostnames, or client configuration.

## Immutable agent resources

The separate `agent-resources` package contains pinned skill trees without
adding them to the default toolchain or development shell:

```sh
nix build .#agent-resources
```

Its skills are rooted at `share/agent-resources/skills/<name>` in the output.
Pinned Pi extensions are rooted at
`share/agent-resources/pi-extensions/<name>`; they are immutable extension
trees for direct linking, not registrations or mutable `pi install` state.

## Managed agent wrappers

`lib.patchAgentPackage` adds managed-config selection to the Claude, Codex,
and Droid packages. A wholly absent managed artifact set delegates unchanged,
a complete regular-file set selects the managed configuration, and a partial
or invalid set fails closed. Set `AI_NIX_BYPASS_MANAGED_CONFIG=1` for explicit
recovery without disabling the wrappers' pre-existing host-local behavior.
The Claude package also exposes `claude-real` for callers that deliberately
need the unwrapped executable.

The separate `agent-http-header-bridge` package is the narrow HTTPS header
bridge used by Droid MCP entries:

```sh
nix run .#agent-http-header-bridge -- \
  https://example.invalid/mcp Authorization API_TOKEN
```

Its final argument names a required environment variable; the credential is
resolved only inside the bridge process and is never passed in its argv.

## Checks

The flake exposes the repository checks as apps, so CI, lefthook, and local
work all call the same targets:

```sh
nix run .#format          # rewrite Nix and shell formatting
nix run .#format-check    # check formatting
nix run .#lint            # statix, deadnix, and ShellCheck
nix run .#test            # flake and output evaluation smoke tests
nix run .#build-check     # nix build .#default
nix run .#no-warnings     # build with Nix warnings treated as errors
nix run .#coverage-check  # check quality coverage against the baseline
nix run .#profile-check   # check profiling numbers against the baseline
nix run .#fuzz            # randomized Nix parser smoke target
nix run .#memory-check    # report sanitizer applicability
nix flake check
```

There's no ordinary line-coverage story for a Nix overlay repository. The
coverage target instead reports whether every Nix and shell file is covered by
the formatter/linter/check net. That's the useful number here. The fuzz target
is similarly modest: Nix doesn't have a sanitizer-guided fuzz setup in this
repository, so the target reparses every Nix file repeatedly in randomized
orders.

To install the local hook:

```sh
nix develop --command lefthook install
```

## Updating

The overlays intentionally stay close to their upstream package definitions.
When refreshing one of them, update the matching file under `overlays/`, then
run:

```sh
nix flake lock
nix run .#format
nix run .#check
```

Keeping these checks boring is the point: if the shell stops building, I want
to find out before I try to use it in the middle of something else.

Fractal is exposed as `plasma-fractal` because Nixpkgs already uses `fractal`
for the GNOME Matrix client. Keep the Fractal and Wiki package versions and
skill-resource checks aligned when updating either wheel.
