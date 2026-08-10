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
`3278f5fc..842ce675`, followed by a partner-observation cleanup. The signed
commits and current tests are the durable evidence; the transient untracked
observation queue has been consumed. Five findings were adjudicated rather than
applied, with the rationale recorded below or beside the code they concern;
unresolved authority questions requiring live or downstream evidence are listed
separately below:

- the preflight allowlist stays leaf-granular (comment at its declaration
  in `config/ai/preflight.nix`);
- the Pi normalization policy keeps two validators with distinct roles
  (comments in `packages/pi-gallery/default.nix` and `bin/update-overlay`);
- signature acceptance remains independently enforced at its trust and
  packaging boundaries (comment in `test/bin/quality`);
- replacing the large update-overlay dispatcher remains a separately scoped
  parity spike, not a speculative cleanup refactor;
- Pi's mutable-state guard, runtime packages, and activation remain
  composer-owned lifecycle policy; a generic renderer channel waits for a
  second concrete client requirement rather than moving ownership speculatively.

### Open questions blocking the remaining items

Owner-decided review work is tracked in [`PLAN.org`](PLAN.org); only these
authority questions remain unresolved:

1. `config/ai/skills/node-red/SKILL.md` instructs reading
   `/run/secrets/node-red-admin-token`, contradicting the binding security
   rule: host-side helper, or documented exception?
2. Does anything downstream run the portable lint stack
   (`config/ai#apps.{format,lint,check}`)? Nothing in this repository does,
   and it has drifted weaker than `test/bin/quality`.
3. Do clio's `~/Models/llama-swap.yaml` and omlx state serve the model IDs
   its codex profiles now advertise (`GLM-5.2`,
   `Qwen3.6-27B-oQ6e-mtp`)? The catalog asserts the services exist on both
   workstations; model inventory is unmanaged host state.
