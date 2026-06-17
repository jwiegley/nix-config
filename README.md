# ai-nix

A portable Nix development shell for AI CLI tools, local LLM utilities, and MCP
servers.

Run:

```sh
nix develop
```

The default shell includes:

- agent CLIs from `llm-agents.nix`: `claude`, `ccusage`, `codex`, `droid`,
  `gemini`, `mcporter`, and `opencode`
- `git-ai` in its minimal form, so `git-ai` is available without replacing
  `git` in the shell
- Simon Willison's `llm` CLI with the MLX plugin on Apple Silicon
- local inference and model tooling: `llama.cpp`, `llama-swap`, `gguf-tools`,
  `hfdownloader`, `guidellm`, `qdrant`, and `qdrant-web-ui`
- Apple Silicon MLX tools when available: `mlx-lm`, `mtplx`, `omlx`, and
  `vllm-mlx`
- MCP servers and agent helpers: PAL, Sequential Thinking, Context7,
  Playwright, GitHub, Context Hub, Rust docs, Drafts on macOS, and Sherlock
- Claude transcript/config tools: `claude-vault`, `claude-replay`, and `agnix`

The shell sets non-secret runtime defaults for AI tooling: updater suppression,
Hugging Face transfer support, and CA variables. It does not include API keys,
personal paths, private hostnames, or MCP client configuration.

## Updating

This repository intentionally keeps the custom package overlays close to their
source package definitions. To refresh them, update the matching AI-specific
overlay files, then run:

```sh
nix flake lock
nix fmt
nix develop --command true
```
