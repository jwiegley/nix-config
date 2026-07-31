# Technical vocabulary and phonetic corrections

Canonical spellings and capitalizations, plus the phonetic-correction table for common speech-to-text mishearings. Always correct a matched term to its canonical form here.

## Canonical spellings and capitalizations -- always correct to these

**Languages and runtimes:**
Rust, C++ (from "C plus plus"), Haskell, Python, Lisp, Emacs Lisp, Common Lisp, Clojure, Scheme, Erlang, Elixir, OCaml, Scala, Zig, Go, Lua, Julia, TypeScript, JavaScript, Bash, Zsh, Fish, POSIX shell, Swift, Kotlin, Ruby, Java, C#, F#, Nim, Mojo, CUDA, WGSL, GLSL, SQL

**AI / ML terms:**
LLM, GPU, CPU, TPU, VRAM, GGUF, GGML, GPTQ, AWQ, EXL2, LoRA, QLoRA, transformer, attention, self-attention, multi-head attention, softmax, logit, logits, perplexity, tokenizer, tokenization, BPE (byte-pair encoding), embedding, fine-tuning, fine-tune, inference, quantization, quantized, dequantize, RLHF, DPO, PPO, SFT, RAG, MoE, KV cache, context window, context length, prompt, system prompt, temperature, top-p, top-k, sampling, greedy decoding, batch size, epoch, gradient, backprop, backpropagation, loss function, cross-entropy, cosine similarity, BLEU, ROUGE, F1, precision, recall, PyTorch, TensorFlow, JAX, Flax, NumPy, SciPy, pandas, Hugging Face, Transformers (the library), Safetensors, llama.cpp, llama-swap, vLLM, Ollama, MLX, ONNX, TensorRT, OpenAI, Anthropic, Claude, GPT, Gemini, Llama, Mistral, Mixtral, DeepSeek, Qwen, Phi, Stable Diffusion, Midjourney, DALL-E, MCP, Model Context Protocol, tool use, function calling, agentic

**Rust ecosystem:**
cargo, crate, crates.io, rustc, rustup, rustfmt, clippy, tokio, async, await, impl, trait, struct, enum, match, Option, Some, None, Result, Ok, Err, Vec, Box, Rc, Arc, RefCell, Mutex, RwLock, Pin, Future, Send, Sync, lifetime, borrow checker, ownership, move semantics, serde, serde_json, clap, anyhow, thiserror, tracing, tower, axum, warp, actix, no_std, unsafe, repr, derive, proc macro, attribute macro

**Haskell / FP terms:**
GHC, GHCi, Cabal, Stack, Hackage, Hoogle, monad, monoid, functor, applicative, foldable, traversable, IO, Maybe, Just, Nothing, Either, Left, Right, typeclass, type class, newtype, data, where, let, in, do notation, lens, prism, optic, profunctor, Yoneda, Kan extension, lazy evaluation, thunk, strictness, bang pattern, Haskell Language Server, HLS

**Emacs / Lisp:**
Emacs, Neovim, Vim, Org mode, org-mode, Org-roam, Magit, TRAMP, Dired, Helm, Ivy, Vertico, Consult, Orderless, use-package, straight.el, Elpaca, Evil mode, major mode, minor mode, buffer, window, frame, kill ring, yank, defun, defvar, defcustom, setq, let, lambda, progn, cond, elisp, Emacs Lisp, S-expression, sexp, cons, car, cdr, nil, t, SLIME, Sly, SBCL, Quicklisp, ASDF, Paredit, Smartparens

**Shell / CLI / systems:**
Bash, Zsh, Fish, POSIX, stdin, stdout, stderr, pipe, pipeline, redirect, glob, regex, grep, sed, awk, jq, yq, curl, wget, ssh, scp, rsync, tmux, screen, Docker, Podman, Kubernetes, k8s, Nix, NixOS, Homebrew, brew, systemd, journalctl, cron, crontab, Git, git, GitHub, GitLab, Bitbucket, CI/CD, GitHub Actions, Makefile, CMake, Meson, Bazel, GCC, Clang, LLVM, GDB, Valgrind, strace, dtrace, perf, ELF, DWARF, ABI, FFI, cdylib, staticlib

**Networking / infra:**
TCP, UDP, HTTP, HTTPS, gRPC, REST, GraphQL, WebSocket, JSON, YAML, TOML, Protobuf, MessagePack, CBOR, DNS, TLS, SSL, mTLS, QUIC, IP, IPv4, IPv6, SSH, ARP, ICMP, NAT, DHCP, VLAN, Thunderbolt, USB, PCIe, NVMe, DMA, API, SDK, CLI, GUI, TUI, REPL, localhost, 127.0.0.1, 0.0.0.0

**Hardware / Apple:**
M1, M2, M3, M4, M1 Ultra, M2 Ultra, M3 Ultra, M4 Ultra, M1 Max, M2 Max, M3 Max, M4 Max, M1 Pro, M2 Pro, M3 Pro, M4 Pro, Apple Silicon, Rosetta, Metal, MPS, macOS, iOS, iPadOS, Sonoma, Sequoia, Ventura, ARM, ARM64, AArch64, x86, x86_64, AMD64, RISC-V

## Phonetic corrections -- common speech-to-text mishearings

```
"see plus plus" / "C plus plus"            -> C++
"see sharp"     / "C sharp"                -> C#
"F sharp"                                  -> F#
"pie torch"     / "pie-torch"              -> PyTorch
"tensor flow"                              -> TensorFlow
"jake's"        / "jacks" (in ML)          -> JAX
"num pie"       / "numb pie"               -> NumPy
"site pie"      / "psy pie"                -> SciPy
"my sequel"     / "my S.Q.L."              -> MySQL
"post gress"    / "postgres"               -> PostgreSQL or Postgres
"reddis"        / "read us"                -> Redis
"E max"         / "he max"                 -> Emacs
"nix OS"        / "nick sauce"             -> NixOS
"home brew"     / "home bru"               -> Homebrew
"get hub"       / "git hub"                -> GitHub
"get lab"                                  -> GitLab
"doc her"       / "docker"                 -> Docker
"cube CTL"      / "cube control"           -> kubectl
"llama see PP"  / "llama C.P.P."           -> llama.cpp
"llama swap"                               -> llama-swap
"V LLM"                                    -> vLLM
"oh llama"      / "all llama"              -> Ollama
"Laura"         / "Lora"  (in ML)          -> LoRA
"Q Laura"       / "Q Lora"                 -> QLoRA
"GG UF"         / "G guff"                 -> GGUF
"rag" (retrieval context)                  -> RAG
"moe"           / "M.O.E." (model context) -> MoE
"KV cash"       / "K.V. cache"             -> KV cache
"sarah D"       / "sir D"                  -> serde
"clap" (Rust argument parsing)             -> clap
"axe um"        / "ax um"                  -> axum
"talk ee oh"    / "Tokyo"  (Rust async)    -> tokio
"magic"         / "ma git" (Emacs Git)     -> Magit
"org mode"      / "or mode"                -> Org mode
"S expression"  / "sex P"                  -> S-expression
"car" (Lisp first element)                 -> car
"could er"      / "cutter" (Lisp rest)     -> cdr
"cons" (Lisp construct)                    -> cons
"repo"                                     -> repo
"dev ops"                                  -> DevOps
"M.C.P."        / "MCP"                    -> MCP
"pal"           / "PAL" (PAL MCP Server)   -> PAL
"Claude code"                              -> Claude Code
"G.H."          / "G H" (GitHub CLI)       -> gh
```
