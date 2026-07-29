# Fleet Configuration Programme — Decision Gate

This document is the single up-front gate for the programme's open decisions. It
exists so that each decision is made **deliberately**, by the person who owns it,
rather than defaulted into by whoever next touches the code. It is the artifact
called for by [issue #20](https://github.com/jwiegley/nix-config/issues/20)
(`E1-GAP-DECISIONS`).

Two families of entry appear below:

- **Programme decisions** (`Q1`…`Q8`) — Q1/Q4/Q5/Q6/Q7 remain unanswered;
  Q2/Q3/Q8 have human answers recorded in place. Each carries the question, what
  breaks if it is defaulted, the real options, and a recommendation *only where
  there is evidence for one*. An unanswered slot is human input, never an agent
  choice.
- **Settled decisions** (`S1`…`S8`) — already decided, recorded here as context so
  they are not silently re-opened. Each names where it was settled and on what
  basis. These are **not** open slots.

## Gate invariant (machine-checkable)

```
DECISION_ENTRY_COUNT: 8
```

```bash
# Number of Q decision entries, answered or unanswered:
grep -cE '^Q[0-9]+' doc/FLEET-DECISIONS.md      # == 8

# Total answer slots. FIXED at 14 (Q4 and Q5 carry per-subject sub-slots), so this
# is a real invariant: it changes only when a decision is added or removed.
grep -cE '^- \*\*Answer' doc/FLEET-DECISIONS.md                      # == 14

# Still-unanswered slots. This is a PROGRESS counter, not an invariant -- it must
# fall monotonically to 0 and is not pinned to any number. Pinning it (it once read
# "== 14") makes the check fail the moment an answer lands, which trains a reader to
# ignore it.
grep -cE '^- \*\*Answer.*_\(unanswered\)_' doc/FLEET-DECISIONS.md  # falls to 0

# Settled entries carried as context (not counted as open):
grep -cE '^S[0-9]+' doc/FLEET-DECISIONS.md      # == 8
```

Every programme decision line begins `Q<n>.` at column 0; every settled line begins
`S<n>.`. Verbatim quotations of the original questions live inside a table (lines
beginning `|`) so they are **not** counted by the `^Q` grep.

---

## Provenance — the original "six open issue-15 decisions", verbatim

Issue #20 was written against six questions recorded in the issue-15 remaining-scope
handoff (§"Open questions requiring explicit decisions"). They are reproduced here
verbatim, each mapped to its classification in *this* gate. **Do not read issue
#20's framing as still-current:** of the six, one is now settled by standing policy,
and the live programme has surfaced three further open decisions that issue #20
never contained.

> Note on numbering: these `I15-Q*` labels are the *original* handoff numbers. This
> gate re-numbers its decision entries `Q1…Q8` for a clean, countable set. `FLEET-DESIGN-PLAN.md`
> §10 also uses `Q1…Q7`, for a **different** set (the taken architecture decisions);
> those appear here as `S1`–`S5`. The three schemes are distinct — cross-references
> are always given explicitly.

| Original | Question (verbatim) | Classification in this gate |
|---|---|---|
| I15-Q1 | What single mechanism should own npm manifest normalization so Nix packaging and lock generation cannot drift? | **Open → Q1** |
| I15-Q2 | Should direct `bin/update-overlay` always delegate compound work to the isolated `update-agents` candidate transaction, or should the catalog command itself gain an equivalent candidate mode? | **Open → Q2** |
| I15-Q3 | Which fixed root inputs are package-producing policy pins versus ordinary lock-owned infrastructure? | **Open → Q3** (private-remote/`file://` policy already **settled**, S6) |
| I15-Q4 | Which external consumers still require global Anvil mode, Node-RED templates, `flake-ai.nix`, or fallback imports? | **Open → Q4** |
| I15-Q5 | When will native Clio, Andoria, Vulcan, and VPS routes be available? | **Open → Q5** (scheduling, not a design fork) |
| I15-Q6 | Will activation be separately authorized after native evidence is complete? | **Settled → S1** (standing policy: yes, always) |

Three further decisions, absent from issue #20 and originally flagged "needs a
decision / your call" in their own issues, were added as **Q6, Q7, Q8**. Q8 has
since been answered; Q6 and Q7 remain open.

---

# Programme decisions — unanswered slots require a human answer

Each slot records: **Answer**, **Date**, **Decided by**, and **Follow-up** (the
downstream item(s) to update once answered). Leave an unanswered slot exactly as
printed until a decision is made; do not substitute a recommendation for an answer.

---

Q1. What single mechanism should own npm manifest normalization, so the Nix packaging policy and the updater's lock generation cannot drift?

- **Origin / unblocks:** I15-Q1 → [#39](https://github.com/jwiegley/nix-config/issues/39) (`E2-WU4C-NPM`, WU4c-1.2). Cross-stream coupling X2: Pi-fleet WU6/WU8 ([#61](https://github.com/jwiegley/nix-config/issues/61)/[#66](https://github.com/jwiegley/nix-config/issues/66)) assert identity against the manifest/lock pairing, so this must land **before** them or those assertions become meaningless.
- **Type:** engineering. The *direction* is already settled — there must be exactly one shared authority, and it is computed inside the isolated candidate transaction (see the reverted-unsafe `a88a77ba` / revert `a98385b9`, and Q2). What is open is **where that one authority lives**.
- **Why it matters if defaulted:** the **nine** Pi npm targets do not build from the raw upstream `package.json`
  (corrected 2026-07-29: this said "six". Measured — nine committed locks exist under
  `packages/pi-gallery/locks/`, and all nine are `pending` with no executor: betterwright,
  pi-artifacts, pi-dynamic-workflows, pi-hashline-edit-pro, pi-insights, pi-lens,
  pi-markdown-preview, pi-subagents, pi-web-access. `betterwright`, `pi-markdown-preview`
  and `pi-subagents` landed in `04af0e22`/`e0ed94fa` and `pi-dynamic-workflows` in
  `777fe62b`, all after this text was written. Whatever authority Q1 chooses must cover
  all nine or the three omitted keep exactly the drift Q1 exists to remove.); the derivation first *normalizes* it (strips dev/peer deps, applies per-package removals) and pairs it with a committed `package-lock.json`. The reverted attempt generated locks from the *published* manifest, which is not what the derivation builds — a silent drift that ships a lock inconsistent with the package. If the next implementer re-derives normalization independently in the updater, the drift returns.
- **Options:**
  - **(a) Extract the derivation's inline normalization** (`packages/pi-gallery/default.nix`) into one importable module that *both* the build and `bin/update-overlay` consume. One source of truth; both paths provably identical.
  - **(b) Have the updater invoke the derivation's own normalization** at update time (no extraction), treating the build as the authority. Avoids a new module but couples the updater to derivation internals.
  - **(c) Declare the normalized manifest itself a committed catalog artifact** the updater regenerates and the derivation consumes verbatim. Most explicit, but adds a generated file per target.
- **Recommendation (evidence-based, not a decision):** (a). The normalization policy already exists inline in the derivation and the recorded hazard was precisely the updater using a *different* manifest; a single extracted authority both sides import is the narrowest seam that makes drift structurally impossible. No evidence favors (b) or (c) over (a).
- **Answer:** _(unanswered)_
- **Date:** _______  **Decided by:** _______  **Follow-up:** update #39 acceptance to name the chosen authority; confirm #61/#66 assert against it.

---

Q2. Should `bin/update-overlay` **delegate** compound work to the isolated `update-agents` candidate transaction, or should the catalog command gain its **own** equivalent candidate mode?

- **Origin / unblocks:** I15-Q2 → [#33](https://github.com/jwiegley/nix-config/issues/33) (`E2-WU4C-COMPOUND`, WU4c-1.1), the foundation for all later compound executors (1.2–1.5).
- **Type:** engineering. The *invariant* is settled — #33 makes isolated-candidate computation the mandatory home for compound updates, so no compound work ever mutates the authoritative tree while dependent hashes are still being computed. What is open is **which command owns the isolation machinery**.
- **Why it matters if defaulted:** the reverted `a88a77ba` mutated catalog and lock files in place while still computing hashes; an interruption could commit fake hashes or partial projections. If `update-overlay` grows a *second*, independently-written candidate mode, there are now two isolation implementations to keep correct, and the weaker one becomes the hazard. If it delegates, there is one.
- **Options:**
  - **(a) `update-overlay` delegates** all compound work to the existing `update-agents` detached-worktree transaction (repository-scoped lock, complete validated patch, fast-forward publish only). One implementation; direct invocations route through it.
  - **(b) A single shared transaction helper** factored out of `update-agents`, called by both entry points. Same one-implementation guarantee, but neither command is subordinate to the other.
  - **(c) `update-overlay` gains its own candidate mode** mirroring the discipline. Independent, but duplicates the safety-critical code.
- **Recommendation (evidence-based, not a decision):** (a) or (b) over (c). The programme's stated rule is "fix root causes at the narrowest shared seam"; two copies of interruption-safe transaction code violates it. No evidence distinguishes (a) from (b); that choice is genuinely open.
- **Answer:** **(a)** — `bin/update-overlay` delegates all compound work to `bin/update-agents`' existing detached-candidate-worktree transaction. A direct `update-overlay <compound-target>` refuses and routes rather than computing in the authoritative tree. Option (c) is ruled out by the code, not by preference: `update-overlay`'s own `SourceTransaction` (`bin/update-overlay:1093`) is a soft in-process restore, so the only interruption-safe isolation is `update-agents`' worktree (`:192`), repo-scoped lock (`:183`), inventory-derived allowlist (`:227-247`) and ff-merge-only publish (`:275-288`); reimplementing that in Python duplicates safety-critical logic. (a) over (b) is the maintainer's ratification, not a code verdict — the bash/Python boundary is neutral between them, since under both a Python entry point ends up invoking bash transaction code.
- **Date:** 2026-07-29  **Decided by:** John Wiegley  **Follow-up:** record in #33/#38; the known cost is that `update-agents`' transaction also refreshes both flake locks, runs nixfmt and two flake checks and creates a signed commit, so a narrow source-hash bump needs either that whole pipeline or a narrower entry point inside `update-agents` (switch/push stay gated).

---

Q3. Which fixed root inputs are **package-producing policy pins** (to be cataloged as validated projections) versus **ordinary lock-owned infrastructure**?

- **Origin / unblocks:** I15-Q3 → [#34](https://github.com/jwiegley/nix-config/issues/34) (`E2-WU4C-ROOT-INPUTS`, WU4c-1.6); its allowlist also gates the completeness gate [#25](https://github.com/jwiegley/nix-config/issues/25) (1.7).
- **Type:** engineering / policy. The *source-kind policy* is already settled (see **S6**): local `file://` is always forbidden; private `git+ssh` (stock-trader) is valid, scoped by unauthenticated *fetchability* not by validity. What is open is the **partition of the remaining fixed inputs**.
- **Why it matters if defaulted:** the completeness gate (1.7) flags any literal Internet coordinate not declared in the catalog. If a package-producing pin (e.g. `obr`, `org2jsonl`, `stock-trader`, `rust-overlay`, and the 8 `flake-input` records still in `packages/update-manifest.nix`) is left as a bare `flake.nix` literal, the gate either rejects it or someone silences the gate — reintroducing exactly the "undeclared coordinate" problem the gate exists to catch. Mis-classifying genuine infrastructure as a package pin, conversely, forces spurious update executors onto it.
- **Options:**
  - **(a) Catalog every hand-pinned, package-producing remote** (fixed rev + NAR hash) as a validated projection asserting URL/rev/hash parity against the literal declaration, retaining the literal for Nix evaluation; leave only genuinely lock-owned, unpinned infrastructure lock-owned.
  - **(b) Draw a narrower line** — catalog only those inputs the updater is expected to bump, and add a documented gate exception for the rest.
- **Recommendation:** none on the exact partition — this requires a per-input judgement about which pins are *policy* (deliberately held, updater-owned) versus incidental infrastructure, which is the user's call over their own inputs. The *mechanism* (validated projection retaining the literal declaration; no dynamic flake-input generation) is already fixed by #34's scope.
- **Answer:** **narrow** — catalogue only the inputs the updater is expected to bump: the **11 records currently in `packages/update-manifest.nix`**, so #43 can delete that file. The remaining rev-pinned root inputs stay as bare `flake.nix` literals with no parity assertion. Accepted cost: an input left as a literal has no catalogued version/hash owner. **Two framing errors in this question were corrected before it was answered, so the answer is not a response to the original premise.** (1) The "why it matters" text said an uncataloged input would be rejected by the completeness gate or need silencing; that is counterfactual — #25's gate *deliberately* scopes flake-input locators out (`bin/update-overlay-test.py:1465-1466`: "Deliberately NOT covered … flake INPUT locators (owned by the external-filesystem and whole-closure purity checks above — one mechanism, per cross-stream X4)"). Nothing is being rejected today; the forcing function is purely #43's deletion. (2) The question calls the manifest pins "fixed **root** inputs"; they are portable `config/ai` subflake inputs — `rust-overlay` appears 0 times in `flake.nix` and twice in `config/ai/flake.nix`.
- **Date:** 2026-07-29  **Decided by:** John Wiegley  **Follow-up:** record on #34 and #43. Two defects to fix in #34 before implementing: its criterion asks each record to assert "URL/rev/**NAR-hash** parity against the literal declaration", but a `github:` rev literal in `flake.nix` carries no NAR hash — it lives in `flake.lock` — so that criterion is unsatisfiable as written; and `hakyll` (`flake.nix:53-54`) is consumed nowhere in the tree, making it dead-input cleanup rather than a classification subject.

---

Q4. Per compatibility surface — global Anvil mode, Node-RED asset templates, `flake-ai.nix`, and the `nix-ai`/`git-ai` fallback imports — is each **retained** or **retired**?

- **Origin / unblocks:** I15-Q4 → [#53](https://github.com/jwiegley/nix-config/issues/53) (`E7-COMPAT-DECISIONS`: Anvil mode, Node-RED, standalone ai-nix, runtime fallbacks) and [#60](https://github.com/jwiegley/nix-config/issues/60) (`E7-FLAKEAI-RETIRE`: `flake-ai.nix` + fallback). Both are `EPIC 7` decision owners.
- **Type:** policy. The evidence input — the merged cross-consumer inventory ([#17](https://github.com/jwiegley/nix-config/issues/17), now **closed/done**) — exists, so the decision is *answerable now*. The `flake-ai.nix` internal-import migration ([#54](https://github.com/jwiegley/nix-config/issues/54)) is a hard prerequisite before its retirement can be *executed*, but not before the keep/retire *decision* is recorded.
- **Why it matters if defaulted:** CLAUDE.md permits deleting compatibility only after zero maintained-consumer usage is proven, and requires a retained surface to record owner, reason, current consumer, and retirement trigger. Defaulting means either a surface is deleted while a consumer still needs it (breakage), or dead compatibility accretes forever with no owner (the exact rot this programme removes). Each surface needs its own recorded verdict.
- **Options (per surface):** **retain** — record owner, reason, current consumer, concrete retirement trigger; or **retire** — delete only after the #17 inventory proves zero maintained-consumer usage (and, for `flake-ai.nix`, after #54 migrates the four internal imports).
- **Recommendation:** none. The verdict must be read off the #17 inventory of maintained consumers on both remotes; this analysis has not read that inventory and must not guess a consumer's needs.
- **Answer (global Anvil mode):** _(unanswered)_
- **Answer (Node-RED templates):** _(unanswered)_
- **Answer (`flake-ai.nix` + fallback):** _(unanswered)_
- **Date:** _______  **Decided by:** _______  **Follow-up:** record each verdict in #53/#60 with the CLAUDE.md fields; if any is "retire `flake-ai.nix`", sequence after #54.

---

Q5. When will native build routes for **Clio, Andoria, Vulcan, and VPS** be available, so that native evidence can be produced?

- **Origin / unblocks:** I15-Q5 → `EPIC 9` native matrix and the Pi-fleet native phase ([#74](https://github.com/jwiegley/nix-config/issues/74) Phase G native builds, no QEMU; [#70](https://github.com/jwiegley/nix-config/issues/70) fleet store realization; [#71](https://github.com/jwiegley/nix-config/issues/71) four-machine atomic cutover; migration Stages 3/4/5 in `FLEET-DESIGN-PLAN.md` §9). Gates **Q6/S1** (activation needs native evidence first).
- **Type:** scheduling / host-availability — **not a design fork.** This is a commitment about *when each host is reachable for a native build*, not a choice between architectures. It is surfaced because every activation downstream waits on native evidence, and cross-compilation is explicitly refused (Hera's builder route attempted invalid x86-on-ARM QEMU; #74 is "no QEMU").
- **Why it matters if defaulted:** if no schedule is set, the native matrix stalls indefinitely and the programme cannot reach the activation phase; conversely, an implicit assumption that a host is available can trigger an unplanned build on a machine that is not reachable.
- **Options:** commit a per-host window for each of Clio / Andoria / Vulcan / VPS; or explicitly defer a host and record what blocks it (reachability, other in-flight work).
- **Recommendation:** none — host availability is operational information not visible from the repository.
- **Answer (Clio):** _(unanswered)_
- **Answer (Andoria):** _(unanswered)_
- **Answer (Vulcan):** _(unanswered)_
- **Answer (VPS):** _(unanswered)_
- **Date:** _______  **Decided by:** _______  **Follow-up:** record windows against the EPIC 9 native issues; native evidence then unblocks the S1 activation authorizations.

---

Q6. How is the `bin/update-agents` → `bin/update` rename's **PATH collision** resolved, given that `update` is already installed?

- **Origin / unblocks:** [#78](https://github.com/jwiegley/nix-config/issues/78). The issue states plainly it "cannot be completed without a decision," and that the choice is the user's because both tools are theirs.
- **Type:** tooling / policy.
- **Why it matters if defaulted:** `my-scripts` (from the `scripts` input) already installs an executable `update` — a per-repository git fetch/update helper — into the same user profile via `nix-scripts` (`overlays/30-user-scripts.nix`, `src = ../bin`). A naive `git mv` produces **two** executables named `update`, and which one wins depends on profile ordering: precisely the silent ambiguity this programme removes. A `throw`ing stub is not possible for a shell script, so a silent alias at the old name would defeat the rename.
- **Options (collision):** **(a)** rename the `my-scripts` `update` helper; **(b)** retire the `my-scripts` `update` helper; **(c)** choose a different name than `update` for the catalog updater.
- **Sub-decisions the issue also flags:** whether to leave a compatibility wrapper at `update-agents` (#78's own recommendation: do **not** leave a silent alias; a short-lived wrapper that prints the new name and exits non-zero is the honest middle ground if muscle memory is a concern); and that renaming the transaction lock/tempdir (`update-agents.lock`, `update-agents.XXXXXX`) changes the lock identity, so a concurrent old-name invocation would no longer be excluded — decide whether that matters.
- **Recommendation:** none on which tool yields the name — both are the user's tools and the trade-off (which helper is more entrenched in muscle memory) is not visible from the repository. On the shim sub-question, #78's recorded recommendation (no silent alias; optional non-zero-exit wrapper) is sound and evidence-backed. Also worth sequencing **after** [#43](https://github.com/jwiegley/nix-config/issues/43), which removes `packages/update-manifest.nix` and shrinks the rename surface.
- **Answer (collision resolution):** _(unanswered)_
- **Answer (compat shim / lock identity):** _(unanswered)_
- **Date:** _______  **Decided by:** _______  **Follow-up:** record the decision in #78; then execute the rename and the 46 references.

---

Q7. Should Vulcan's two `nix-config` inputs carry `?rev=` pins at all?

- **Origin / unblocks:** [jwiegley/nixos-config#1](https://github.com/jwiegley/nixos-config/issues/1). The maintainer comment records this explicitly as a standing policy preference not being decided unilaterally: "Whether to also pin is a standing policy preference — say the word and it is a two-line change per input."
- **Type:** policy.
- **Why it matters if defaulted:** both Vulcan inputs are **floating** (no `?rev`). A floating input let `nix flake update` drift Vulcan's lock *past* the `a3cc3843` overlay refactor and detonate its whole evaluation (this already fired — Vulcan was found at `03b5eecc`, 29 commits past, unable to evaluate). The routing fix has since landed (Stage 2), so the specific break is repaired; the open question is whether to add `?rev=` as *standing* protection against a future float.
- **Options / trade-offs:**
  - **(a) Pin with `?rev=`** — converts a routine `nix flake update` into an explicit edit-then-update, which is exactly the mechanism that would have prevented the break. Cost: real friction on inputs bumped deliberately and often, and duplicated state between `flake.nix` and `flake.lock` that can silently disagree.
  - **(b) Do not pin** — rely on the durable fixes already landed: the canary and the cross-consumer eval gate ([#22](https://github.com/jwiegley/nix-config/issues/22), closed/done), which make a breaking bump *visible at merge time* rather than merely slower to arrive. Note `flake.lock` already pins an exact revision, so nothing drifts on a normal build regardless.
- **Recommendation:** none — the maintainer has framed this as a standing preference between two defensible postures, and both mitigations for the actual failure mode are already in place. The decision is a two-line change per input either way.
- **Answer:** _(unanswered)_
- **Date:** _______  **Decided by:** _______  **Follow-up:** record in nixos-config#1; if pin, add `?rev=` to both inputs in `nixos/flake.nix`.

---

Q8. Should the public GPG key be committed at `.github/signing-keys/jwiegley.asc`, so the CI signature-verification job is meaningful?

- **Origin / unblocks:** [#23](https://github.com/jwiegley/nix-config/issues/23) (`E1-GOV-SIGNED-CI`). The maintainer comment records: "That is your call because it means committing your public key into a public repository."
- **Type:** security / policy.
- **Why it matters if defaulted:** the verification job is **fail-closed** — a keyring-less run rejects every commit with `[E]` and exits non-zero (deliberately, so a keyring-less CI cannot pass vacuously). The job is meaningful only once the public key (`12D70076AB504679`) is committed at `.github/signing-keys/jwiegley.asc` (verified absent today: `.github/signing-keys/` does not exist). Therefore **the key and the job must land in the same change** — landing the job first turns the next push red; landing it later than the key is strictly worse than landing neither. This coupling is a hard constraint on whatever is decided.
- **Options:**
  - **(a) Commit the public key and the CI job together** — full enforcement. `gpg --armor --export 12D70076AB504679 > .github/signing-keys/jwiegley.asc`. Cost: public (not secret) key material lives in a public repo.
  - **(b) Local-only enforcement** — `bin/quality signatures` already works against the local keyring; no CI job, so CI never verifies signatures.
  - **(c) Use GitHub's own verification API** instead of a committed keyring — a different trust model (relies on GitHub-registered keys for pushed commits).
- **Recommendation:** none on which option — committing personal key material into a public repository is the user's call. The fail-closed coupling (key + job in one change) is a fact to honor whichever option is chosen.
- **Answer:** **(a) rejected** — the public key is **not** to be committed to this repository. Recorded verbatim: "I do not want the key committed." Implemented as **(b) local-only enforcement** in `1aea36cd`, which removed `.github/signing-keys/johnw.asc` and the CI `signatures` job together (Q8's own coupling constraint: key and job land or leave in one change). The pre-push `signatures` hook still runs `bin/quality signatures` against the developer's ambient keyring. **(c)** — GitHub's own verification API, a different trust model — remains available and unchosen; it needs no committed key, so it can be adopted later without revisiting this answer.
- **Date:** 2026-07-29  **Decided by:** John Wiegley  **Follow-up:** recorded on #23. Note for whoever revisits: `aeef544b`/`d8fc36c1` had already committed the key without consulting this gate; `1aea36cd` reverted it before any push, so the key was never published. `bin/verify-signatures`' `--keys-dir` support is retained as an unused capability.

---

# Settled decisions — context, not open slots

These are recorded so they are not silently re-opened. Each is already decided; the
"basis" names where and on what grounds. Where implementation has not yet landed,
that is noted — an unimplemented decision is still a *decision*, not an open question.

S1. Activation is separately authorized after native evidence is complete — **yes, always.**
- **This is the current answer to I15-Q6.** Settled by standing policy: CLAUDE.md ("every system/Home Manager activation … requires explicit authorization for that action") and `FLEET-DESIGN-PLAN.md` §10 Q7 ("Pushing remains separately authorized"). Issue #20 itself states surfacing Q6 "does NOT grant it." There is nothing to decide at this gate; each activation is authorized per-action when its native evidence (Q5) is ready. Presenting it as an open slot would misrepresent a standing invariant as a pending choice.

S2. `config/ai` is renamed to `config/fleet`, with a throwing stub left at `config/ai`.
- **Settled** in `FLEET-DESIGN-PLAN.md` §10 Q5a ("honesty over continuity"), owned by [#47](https://github.com/jwiegley/nix-config/issues/47) (`E3-RENAME`). **Not yet implemented:** `config/fleet` does not exist; the subflake is still `config/ai`. Consequence flagged on the (closed) [#46](https://github.com/jwiegley/nix-config/issues/46)/[#48](https://github.com/jwiegley/nix-config/issues/48): their verification commands reference `./config/fleet`, a path that will not exist until #47 lands. This is a **sequencing note, not a new decision** — the rename decision is made; only its execution is pending, and #63 tracks post-rename stragglers before the stub can be retired.

S3. Two locks, with the existing subflake promoted to the fleet core.
- **Settled** in §10 Q5 (hermetic proof: a middle level merely re-records the child's inputs; the subflake's lock contains neither real-flake blocker). Owned by [#44](https://github.com/jwiegley/nix-config/issues/44) (`E3-FLEET-CORE`).

S4. Dual push; both remotes (gitea, github) stay authoritative.
- **Settled** in §10 Q6 (live proof of need: `main` once reached 7 ahead of gitea but 19 ahead of github). Implemented — [#18](https://github.com/jwiegley/nix-config/issues/18) (`bin/publish`, atomic dual-remote push) is **closed/done**.

S5. Shared `$HOME`; host-local *state* only; one trust domain now; `gpu-server` needs no special packages.
- **Settled** in §10 Q1–Q4, evidence-based (byte-identity holds by construction; `/var/lib/jwiegley` for host-local state; `.sops.yaml` structured to split the trust domain later; zero GPU/CUDA hits, and injecting real hostnames was *measured* to diverge the ssh-config derivation, so uniformity is preserved, not "fixed").

S6. Root-input source-kind policy: local `file://` forbidden; private `git+ssh` (stock-trader) valid, scoped by fetchability.
- **Settled** by [#24](https://github.com/jwiegley/nix-config/issues/24) (**closed/done**): removed the `file:///Users/johnw/src/org2jsonl` leak and recorded the stock-trader `git+ssh` decision — private remotes remain *valid* sources; the argument for keeping them out of a portable/public closure is unauthenticated *fetchability*, not validity. This is the policy the whole-closure lock-purity check ([#36](https://github.com/jwiegley/nix-config/issues/36), closed/done) encodes. It settles the *policy* half of Q3; the remaining *partition* stays open in Q3.

S7. Home Manager release skew is handled by a dual-API ssh shim, not a fleet-wide HM release bump.
- **Settled** by the master-plan strategy row, recorded in [#29](https://github.com/jwiegley/nix-config/issues/29) (`GOV-HMSKEW`): "pick the dual-API shim over bumping fleet-wide HM release … running both is wasted work." Implementation is open in #29; the *choice* is made.

S8. The outstanding host facts are confirmed, not open.
- The §10 "still to confirm on a host" items (`%l` live-expansion in user units, `/nix` locality, which HM profile branch each work machine takes, no auto-GC delete-old timer) are owned by [#21](https://github.com/jwiegley/nix-config/issues/21) (`E1-GAP-HOSTRECON`), now **closed**. They were cheap confirmations that blocked nothing; recorded here so they are not mistaken for open design questions.

---

## Cross-reference summary

| Gate ID | Decision | Owner issue(s) | Blocks / unblocks | Status |
|---|---|---|---|---|
| Q1 | npm normalization authority | #39 | before Pi WU6/WU8 (#61/#66) | open |
| Q2 | compound update isolation ownership | #33 | WU4c 1.2–1.5 | answered: delegate to `update-agents` |
| Q3 | fixed-input partition | #34, gate to #25 | 1.6 → 1.7 | answered: narrow 11-record catalogue |
| Q4 | compat keep/retire | #53, #60 (input #17) | EPIC 7; #60 needs #54 first | open |
| Q5 | native route schedule | EPIC 9 (#74/#70/#71) | activation (S1) | open |
| Q6 | `update-agents`→`update` collision | #78 | the rename; ease after #43 | open |
| Q7 | Vulcan `?rev=` pins | nixos-config#1 | float protection | open |
| Q8 | commit public signing key | #23 | fail-closed CI job (key+job together) | answered: local-only enforcement |
| S1 | activation always re-authorized | policy / §10 Q7 | — | settled |
| S2 | rename to `config/fleet` | #47 (stragglers #63) | — | settled, not landed |
| S3 | two locks / fleet core | #44 | — | settled |
| S4 | dual push | #18 | — | settled, done |
| S5 | shared `$HOME` + host-local state | §10 Q1–Q4 | — | settled |
| S6 | root source-kind policy | #24, #36 | — | settled, done |
| S7 | HM-skew dual-API shim | #29 | — | settled |
| S8 | host facts confirmed | #21 | — | settled, done |
