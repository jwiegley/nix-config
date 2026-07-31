---
name: wiggum
description: Methodology for the user-triggered /wiggum command (do not self-invoke).
  An autonomous-continuation loop for long-running work -- run, checkpoint, and verify
  until a defined Definition of Done holds or a stop-and-escalate condition fires.
  Covers durable handoff state, baseline re-verification after context compaction,
  per-commit self-audit, work-unit commit and restack cadence, subagent fan-out limits,
  host-conditional anvil (live Emacs) tooling, and escalation.
---
# Wiggum

Run autonomously in a work -> checkpoint -> verify loop until the Definition of Done holds, or a stop-and-escalate condition fires. This skill is the methodology; the `/wiggum` command turns it on. Do not enter this mode on your own -- only when the user invokes it.

You perform git operations directly, following the documented approach of the matching workflow. `commit`, `restack`, and `rebase` are user-triggered commands, so follow their procedure rather than invoking them as slash commands.

"Parity" means the work matches a named reference target (for example, a source-of-truth implementation). If no target is given, "done" means every objective of the current plan is complete and independently verified.

## Definition of Done

Exit the loop ONLY when ALL of these hold, with evidence rather than self-assertion:

- Every planned task or done-criterion is complete.
- The build and the full test suite pass, and you have shown the passing output.
- The last work commit has passed a final `fess` audit -- audit it even if the most recent commits were themselves `fess` fixes.
- No actionable partner observation is outstanding as of the last cleanup cycle. (Partner review does not necessarily drain to empty; you may finish with a note that further, non-blocking observations are deferred.)
- The branch is rebased or restacked cleanly onto its base (locally).
- If a parity target was given, a parity check passes with evidence.

Never edit the plan or the done-criteria to lower the bar. Never weaken, skip, or delete tests, and never hardcode outputs to satisfy a check -- that is reward hacking, and it defeats the whole loop (see the `fix-all` skill's philosophy). Verification comes from a separate evaluator, not from grading your own work.

## Stop and escalate

Autonomy is not stubbornness, and these conditions OVERRIDE the /wiggum directive to keep going -- when one fires, stop and hand back to the human, even mid-loop. Stop and ask when:

- the same failing signature or gate persists after a bounded number of attempts (default 3) without intervening progress -- do a root-cause pass, then escalate instead of thrashing. Record the attempt count in the handoff document so it survives compaction, and reset it when the gate passes or the underlying cause demonstrably changes;
- requirements are ambiguous or appear to have changed;
- a rebase or restack conflict cannot be resolved without guessing intent;
- a subagent returns unusable output twice, or PAL consensus cannot be reached;
- an action would be destructive or irreversible -- data loss, force-pushing or submitting shared history, deleting work.

Report where you are, what you tried, and what you need.

## Durable state (survives compaction and fresh sessions)

Keep three distinct artifacts so work resumes exactly where it left off if the machine dies or the session restarts:

1. **Frozen plan / done-criteria** -- the target, written before work. Read-only for the purpose of lowering the bar.
2. **Handoff document** -- what is done, what remains, how to resume, and the current stop-and-escalate attempt counts. Append and trim to keep it current and task-state oriented.
3. **Running learnings** -- if the `journal` workflow is in use, that append-only, timestamped record of durable learnings is separate from the handoff. Do not conflate the two.

## Refresh after compaction

After every context compaction, before any new work: re-read this skill, the frozen plan/target, and the handoff document in full (including the attempt counts); if a journal is kept, re-read its preface plus the recent entries needed to recover the latest learnings. Then run a baseline verification -- build and tests, plus the parity check if a parity target exists -- to confirm the current state before touching anything new. Starting new work on an already-broken base only makes it worse.

## The loop

Each iteration:

1. Advance one logical unit of work -- a coherent change that builds and passes. However, if that logic unit is very small, then proceed in larger steps so that commits are not being generated too often -- since that feedback loop takes a lot of time, and doing so too frquently would slow down development unnecessarily.
2. Commit it in a clean, logical sequence, following the `commit` workflow's approach (you perform the commits directly; `commit` is user-triggered).
3. Audit that commit: dispatch a subagent -- the `fess-auditor` agent, or one running `fess` -- to check the work and its claims. Keep the evaluator separate; do not grade your own work. See `references/fess-audit.md` for how to pick the audit scope and what context snapshot to provide. Verify any finding before acting, and fold real fixes into the main work. Do not separately re-audit commits whose only purpose is to fix `fess` findings, nor `partner-cleanup`'s own cleanup commits (it self-verifies) -- that loops without progress.
4. Check `doc/observations/`; if non-hidden Markdown is present, run `partner-cleanup`, let it make its cleanup commit, then resume.
5. On cadence (below), bring the branch current: rebase or restack it LOCALLY onto its base, resolving conflicts with the `resolve` workflow. Do NOT submit or push the stack as part of the loop -- pushing rewritten or shared history is a terminal, human-gated action (see Stop and escalate).
6. Repeat until the Definition of Done holds or a stop condition fires.

## Cadence -- by work, not by clock

You cannot track wall-clock time reliably across turns, so anchor cadence to work, not minutes:

- Commit at each completed logical unit.
- Rebase or restack before starting a new independent unit, or whenever the base may have moved -- staggered from commits so a restack and a commit never collide in the same step.

Do not batch many units into one giant commit, and do not thrash by committing or restacking mid-unit.

## Keep the branch current

Keep the branch rebased on its base as you go: on a Graphite stack follow the `restack` procedure (rebase from the base of the stack up to the current branch, not above); off Graphite, `rebase` and `resolve`. In the loop this is a LOCAL currency operation only -- submitting or pushing the stack is a separate, human-gated step, never part of the cadence.

## Parallelize non-interfering work

Use the `parallelize` skill. As coordinator you keep all git and shared-state changes in this session and dispatch only safe, non-interfering work -- research, isolated file generation, the `fess` audit, reviews -- to subagents that write only inside their own namespaces and return artifacts you integrate. Bound fan-out to what you can review (roughly 3-5 at a time), and do not let subagents spawn their own subagents.

## Use Anvil where the host provides it

At loop start -- and again as part of every post-compaction refresh -- check whether the single `anvil` MCP registration is available on this host. Probe an advertised capability appropriate to the backend: `emacs-eval` for Emacs-backed mode, or a typed host/file tool for NeLisp. Dedicated mode advertises typed tools such as `file-batch` under the same `anvil` registration (for example `mcp__anvil__file_batch` in Claude Code); the retired `anvil-tools` sibling must not be required. If Anvil is available, invoke the `anvil` skill once and follow its tool-selection rules for the rest of the loop: progressive-disclosure reads for large files, batched typed edits (`file-batch` / `file-batch-across`) over one-at-a-time writes, the org tools for any org-file work, structured git queries for repo state, and async eval for heavy Emacs-side operations. Anvil's live-session safety rules apply unchanged inside the loop -- in particular the unsaved-buffer check before disk edits.

If the tools are absent, note that once in the handoff document and proceed
with standard tools. If a probe fails, follow the Anvil skill's bounded
recovery policy: fall back only for the current operation, then reprobe at the
next mandatory checkpoint or after ten minutes. Never turn one failed probe
into a loop-wide Anvil disablement -- Anvil is an amplifier, never a hard
dependency of the loop.

## Confer via PAL for real decisions

For genuine plans, designs, significant decisions, or critical reviews -- not routine steps -- use PAL MCP to reach consensus with the strongest available reasoning models (currently `gpt-5.5-pro` and `gemini-3.1-pro-preview`). Think deeply, gather the relevant context, and let the consensus shape the plan.
