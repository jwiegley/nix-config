# Current Work

Project 9 is complete. Its source, fleet deployment, Pi qualification, and
closeout evidence are recorded in GitHub Project 9 and issue `#98`. No Project
9 work remains active.

The optional Pi soak procedure remains available in
[`PI-EIGHT-HOUR-SOAK.md`](PI-EIGHT-HOUR-SOAK.md) for manual use when requested;
another soak is not a pending acceptance gate.

## 2026-08-09 whole-repository review: closed

A seven-pass heavy review (94 findings, consolidated to 41 clusters) was
fixed across eight adversarially verified batches, commits
`3278f5fc..842ce675`. Per-finding evidence lives in `doc/observations/`
(untracked by design); two findings were adjudicated rather than applied,
with the rationale committed beside the code they concern:

- the preflight allowlist stays leaf-granular (comment at its declaration
  in `config/ai/preflight.nix`);
- the Pi normalization policy keeps two validators with distinct roles
  (comments in `packages/pi-gallery/default.nix` and `bin/update-overlay`).

### Open questions blocking the remaining items

1. Is `git-ai` genuinely shared-work? Routing says yes, the registry's
   `sharedWorkMembers` says no; the answer gates unifying the shell host
   tables with `config/hosts/registry.nix`.
2. `config/ai/skills/node-red/SKILL.md` instructs reading
   `/run/secrets/node-red-admin-token`, contradicting the binding security
   rule: host-side helper, or documented exception?
3. HTTP-header MCP transport: retained capability or fossil? The bridge
   package, `mcp-remote` input, renderer branches, and 655-line oracle all
   ship while the `mcpHttpHeaders` allowlist has been empty since
   `1b9ffb9c`.
4. Does anything downstream run the portable lint stack
   (`config/ai#apps.{format,lint,check}`)? Nothing in this repository does,
   and it has drifted weaker than `test/bin/quality`.
5. `overlays/10-coq.nix` defines 26 attributes no host or check selects:
   kept for interactive `./build pkg` use, or removable?
6. Do clio's `~/Models/llama-swap.yaml` and omlx state serve the model IDs
   its codex profiles now advertise (`GLM-5.2`,
   `Qwen3.6-27B-oQ6e-mtp`)? The catalog asserts the services exist on both
   workstations; model inventory is unmanaged host state.
