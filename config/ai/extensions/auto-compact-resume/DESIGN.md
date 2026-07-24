# Automatic Compaction and Resumption Design

## Purpose

Long tool-driven Pi runs can cross a model's usable context boundary before Pi's built-in post-run compaction check executes. With `openai/gpt-5.6-sol`, Pi deliberately uses the 272,000-token short-context tier while the model permits as many as 128,000 output tokens. A request issued too near that boundary can therefore end with `stopReason: "length"` before the work is complete.

This extension compacts at a turn boundary before Pi issues the next model request. When compaction interrupts unfinished work, it starts a continuation turn immediately and requires no user response.

## Scope

The extension source, tests, and design records live under `config/ai/extensions/auto-compact-resume`. Home Manager owns only the runtime leaf `~/.pi/agent/extensions/auto-compact-resume/index.ts`; tests and documentation are not installed into Pi's profile. The extension uses only Pi's public API and has no external dependencies. Pi's other mutable profile state remains outside Nix ownership.

The policy derives its threshold from the active model rather than naming GPT-5.6 Sol explicitly, so model switches retain coherent behavior.

## Trigger policy

For an active model, define the safe request threshold as:

```text
contextWindow - maxTokens - 16,384
```

The final term is a safety margin for context-estimation error and request framing. The threshold has a floor of 16,384 tokens for models whose advertised maximum output approaches their complete context window.

For `gpt-5.6-sol`, the calculation is:

```text
272,000 - 128,000 - 16,384 = 127,616 tokens
```

After each `turn_end`, the extension obtains Pi's current context estimate, including trailing tool results. Once the estimate reaches the threshold, compaction begins before another provider request is made. The same check runs on `session_start`, allowing an already-large resumed session to compact while idle.

## Continuation policy

A turn remains unfinished when either condition holds:

- the assistant message contains a tool call, for which Pi would ordinarily issue another model request after executing the tools; or
- the assistant message ended with `stopReason: "length"`, indicating an incomplete response.

The extension records whether continuation is required before starting compaction. Because `ctx.compact()` uses Pi's manual compaction path, it disconnects and aborts the active agent operation before determining whether a compactable boundary exists. The extension must therefore replace that interrupted continuation after both successful compaction and nonterminal compaction failure.

Continuation uses one undisplayed custom message with `triggerTurn: true` and `deliverAs: "followUp"`. This preserves the distinction between the user's actual messages and extension control traffic. A per-turn guard prevents duplicate continuation messages.

A length-truncated answer also resumes when the context is below the compaction threshold. A completed answer may still cause compaction when it crosses the threshold, but it does not cause another model turn.

## Concurrency and failure behavior

An in-memory compaction guard permits only one compaction at a time, and a separate continuation guard permits only one replacement turn. Session startup resets both guards. A resumed session whose current leaf is already a compaction entry does not immediately attempt another compaction.

Pi 0.81.1 applies its configured retry policy to compaction requests before invoking the extension's final `onError` callback. If compaction still fails, the extension clears its guard and defers another compaction attempt until context usage grows by 8,192 tokens. It does **not** defer unfinished work: it immediately queues the replacement continuation when the error is nonterminal. This specifically includes benign refusals such as `Nothing to compact (session too small)` and transient provider failures.

Pi itself emits the visible `Compaction failed: …` event. The extension does not emit a second notification.

Cancellation, abort, missing model selection, authentication, credential, API-key, authorization, billing, or quota errors do not auto-resume because progress requires user action or would create a retry loop. Completed answers likewise never manufacture another turn.

No local extension can continue through process termination or an unavailable provider indefinitely. Within a live process with usable credentials and provider service, a failed or refused compaction cannot strand an unfinished tool-driven or length-truncated turn.

## Verification

Bun tests exercise the extension through a small fake Extension API and establish that:

- GPT-5.6 Sol receives the expected 127,616-token threshold;
- unfinished tool work compacts at the threshold;
- successful compaction emits exactly one hidden continuation turn;
- completed answers compact without continuation;
- length-truncated answers resume with or without compaction;
- `Nothing to compact (session too small)` resumes work and defers only the next compaction attempt;
- transient compaction failures resume without duplicate error output;
- terminal authentication failures do not loop;
- repeated events cannot start concurrent compactions;
- sessions below the threshold remain untouched; and
- a session ending at a compaction boundary is not immediately compacted again.

An explicit Pi 0.81.1 loader smoke test confirms that the repository extension source loads with extension auto-discovery disabled. Home Manager evaluation separately proves that the managed runtime directory contains only `index.ts`; repository tests and JSON checks confirm that unrelated mutable configuration remains untouched.
