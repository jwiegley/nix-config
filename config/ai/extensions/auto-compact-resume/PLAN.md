# Automatic Compaction and Resumption Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Install a global Pi extension that compacts before the active model's safe request boundary and never strands unfinished work when compaction succeeds, fails transiently, or has nothing to compact.

**Architecture:** One TypeScript extension calculates a model-specific threshold, observes `session_start` and `turn_end`, and invokes Pi's public `ctx.compact()` API under a one-operation guard. A hidden custom message with `triggerTurn: true` resumes only work that was demonstrably unfinished. Source, tests, and design stay in this repository; Home Manager installs only runtime `index.ts`.

**Tech Stack:** Pi 0.81.1 extension API, TypeScript loaded by Pi through jiti, Bun's built-in test runner.

## Global Constraints

- Keep Pi's mutable profile outside Nix ownership except for the exact managed runtime leaf `extensions/auto-compact-resume/index.ts`.
- Add no runtime or test dependency.
- Use only public Pi 0.81.1 extension APIs.
- Leave 16,384 tokens beyond the active model's advertised maximum output.
- Never manufacture another turn after a completed answer.
- Never abandon unfinished work merely because manual compaction reports that there is nothing to compact or fails transiently.
- Do not auto-resume after explicit cancellation or a terminal model, authentication, credential, authorization, billing, or quota failure.

---

## File Structure

- `config/ai/extensions/auto-compact-resume/index.ts`: threshold policy and Pi lifecycle integration; the only installed runtime file.
- `config/ai/extensions/auto-compact-resume/index.test.ts`: executable behavior tests using Bun and a minimal fake Extension API.
- `config/ai/extensions/auto-compact-resume/DESIGN.md`: approved behavioral specification.
- `config/ai/extensions/auto-compact-resume/PLAN.md`: this implementation plan.

### Task 1: Specify the lifecycle behavior with failing tests

**Files:**
- Create: `config/ai/extensions/auto-compact-resume/index.test.ts`
- Test: `config/ai/extensions/auto-compact-resume/index.test.ts`

**Interfaces:**
- Consumes: Pi event names `session_start` and `turn_end`; context methods `getContextUsage()` and `compact()`.
- Produces: executable expectations for `calculateThreshold()` and the extension's compaction/resumption behavior.

- [ ] **Step 1: Write the threshold test before `index.ts` exists**

Create a Bun test that dynamically imports `./index.ts`, converts a missing module into `null`, and asserts that the implementation exists and calculates `127_616` for a 272,000-token context, 128,000-token maximum output, and 16,384-token margin.

- [ ] **Step 2: Run the focused test and verify the expected red state**

Run:

```bash
cd config/ai/extensions/auto-compact-resume
bun test index.test.ts
```

Expected: failure because `index.ts` does not yet exist; the assertion reports that the imported module is `null`.

- [ ] **Step 3: Add behavior tests to the same test file**

Use a minimal fake Pi API that records event handlers and calls to `sendMessage()`, plus a fake context that records `compact()` options. Cover these cases:

1. Context below threshold does nothing.
2. A tool-calling assistant turn at threshold compacts exactly once.
3. Repeated turn events while compaction is pending do not compact again.
4. Successful compaction injects one undisplayed `auto-compact-resume` message with `triggerTurn: true` and `deliverAs: "followUp"`.
5. A completed assistant answer compacts when necessary but sends no continuation.
6. A `stopReason: "length"` assistant response resumes both above and below the compaction threshold.
7. `Nothing to compact (session too small)` resumes unfinished work, suppresses duplicate notification, and defers only the next compaction attempt.
8. A transient final compaction failure resumes unfinished work.
9. A terminal authentication failure sends no continuation.
10. A resumed session ending at a compaction entry does not immediately recompact.

- [ ] **Step 4: Re-run and retain the red state**

Run the same `bun test` command. Expected: failure remains attributable to the absent implementation, not malformed test setup.

### Task 2: Implement the guarded global extension

**Files:**
- Create: `config/ai/extensions/auto-compact-resume/index.ts`
- Test: `config/ai/extensions/auto-compact-resume/index.test.ts`

**Interfaces:**
- Produces: `calculateThreshold(contextWindow: number, maxTokens: number): number` and a default Pi extension factory.
- Emits: at most one custom message of type `auto-compact-resume` to replace an interrupted unfinished turn after successful or nonterminal failed compaction, and after low-context output truncation.

- [ ] **Step 1: Implement threshold and unfinished-work detection**

Use this policy:

```typescript
export const SAFETY_TOKENS = 16_384;

export function calculateThreshold(contextWindow: number, maxTokens: number): number {
  return Math.max(SAFETY_TOKENS, contextWindow - Math.max(0, maxTokens) - SAFETY_TOKENS);
}
```

Treat an assistant message as unfinished when it contains a `toolCall` content item or has `stopReason === "length"`.

- [ ] **Step 2: Implement one guarded compaction path**

The helper reads `ctx.getContextUsage()` and `ctx.model.maxTokens`, returns when usage is unknown or below threshold, sets an in-memory guard, and calls `ctx.compact()`. Include compaction instructions that preserve the active goal, completed work, pending work, modified files, errors, and exact next action.

- [ ] **Step 3: Resume through one guarded hidden custom message**

When unfinished work was interrupted by successful or nonterminal failed compaction, call:

```typescript
pi.sendMessage(
  {
    customType: "auto-compact-resume",
    content:
      "Context was compacted automatically while work was in progress. Continue the original user request immediately from the compaction summary. Do not ask for confirmation or merely report status; proceed with the next unfinished action unless genuine user input is required.",
    display: false,
    details: { automatic: true },
  },
  { triggerTurn: true, deliverAs: "followUp" },
);
```

Clear the compaction guard before sending the continuation. On final nonterminal compaction failure, defer another compaction attempt until context grows by 8,192 tokens but continue the interrupted work immediately. Do not duplicate Pi's own compaction error event. Treat explicit cancellation and terminal model, authentication, credential, authorization, billing, and quota failures as requiring external input.

- [ ] **Step 4: Register lifecycle handlers**

On `session_start`, compact an already-large context without resuming unless its leaf is already a compaction entry. On `turn_start`, reset the per-turn continuation guard. On `session_compact`, clear stale compaction deferral. On `turn_end`, derive continuation from `event.message`, run the guarded check, and directly resume a length-truncated response when compaction is unnecessary. Completed sessions below threshold remain untouched.

- [ ] **Step 5: Run tests and verify green**

Run:

```bash
cd config/ai/extensions/auto-compact-resume
bun test index.test.ts
```

Expected: all 12 tests pass with no warnings or errors.

### Task 3: Verify installation against Pi

**Files:**
- Verify: `config/ai/extensions/auto-compact-resume/index.ts`
- Verify: `config/ai/renderers/pi.nix`
- Verify after activation: `~/.pi/agent/extensions/auto-compact-resume/index.ts`

**Interfaces:**
- Consumes: Pi's global extension auto-discovery at `~/.pi/agent/extensions/*/index.ts`.
- Produces: a loadable extension active in new and reloaded sessions.

- [ ] **Step 1: Run a loader smoke test**

Run:

```bash
pi --offline --list-models openai >/tmp/pi-auto-compact-resume-models.txt
```

Expected: exit status zero, `gpt-5.6-sol` appears in output, and Pi reports no extension load error.

- [ ] **Step 2: Reload the current Pi process**

Before the authorized Home Manager switch, verify the repository implementation and tests against the mutable originals, then move the old mutable extension directory to a timestamped backup rather than deleting it. Run the switch, then `/reload` in the interactive session, or restart Pi if external automation cannot submit the command to the current TUI. Because the extension is globally auto-discovered, no `settings.json` registration is required.

- [ ] **Step 3: Verify persisted files and unrelated state**

Run:

```bash
find ~/.pi/agent/extensions/auto-compact-resume -maxdepth 1 -type f -print | sort
python3 -m json.tool ~/.pi/agent/settings.json >/dev/null
git status --short --branch
```

Expected: the repository retains the design, plan, implementation, and test files; the installed extension directory contains only `index.ts`; settings remain valid JSON; and unrelated mutable Pi state is unchanged.

- [ ] **Step 4: Record exact installed paths and verification evidence**

Report every persistent file created, confirm that `settings.json` was not changed, state whether `/reload` remains necessary for the already-running process, and include the test and smoke-test results.
