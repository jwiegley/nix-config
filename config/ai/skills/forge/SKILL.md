---
name: forge
description: 'Multi-phase, multi-model deep analysis workflow for complex problems.
  This skill should be used when the user wants rigorous, multi-model collaborative
  analysis: deep research with Fable/Opus and PAL MCP consensus (GPT-5.5-Pro + Gemini
  3 Pro), strategic planning, Fable/Opus execution with tests, comprehensive review,
  and adversarial devil''s advocate critique. Invoke explicitly with /forge.

  '
---
# Forge: Multi-Model Collaborative Workflow

## Overview

Forge applies maximum analytical rigor to complex problems by orchestrating multiple AI models across six sequential phases:

| Phase | Model(s) | Purpose |
|-------|----------|---------|
| 1. Research | Fable/Opus + GPT-5.5-Pro + Gemini 3 Pro | Deep analysis and consensus |
| 2. Planning | Fable/Opus + GPT-5.5-Pro + Gemini 3 Pro | Strategic plan with validation |
| 3. Execution | Fable/Opus | Code changes + test execution |
| 4. Review | Fable/Opus + GPT-5.5-Pro + Gemini 3 Pro | Comprehensive change review |
| 5. Critique | Fable/Opus + GPT-5.5-Pro + Gemini 3 Pro | Devil's advocate analysis |
| 6. Final Report | Fable/Opus | Summary and remediation loop |

Each analytical phase (1, 2, 4, 5) uses Fable/Opus as orchestrator and builds multi-model consensus via PAL MCP with GPT-5.5-Pro and Gemini 3 Pro. Phase 3 uses Fable/Opus for execution.

## Prerequisites

- The current session must be running on Fable or Opus
- PAL MCP server must be running with access to `gpt-5.5-pro` and `gemini-3.1-pro-preview`
- To verify model availability, call `mcp__pal__listmodels` before starting

If PAL MCP is unavailable or a partner model is missing, inform the user and halt. Do not fall back to single-model operation -- the value of Forge comes from multi-model collaboration.

## Workflow

### Phase 1: Deep Analysis & Research

Conduct thorough investigation of the problem before any planning or coding.

**Step 1.1 -- Explore the problem space:**
- Read all relevant files using Glob, Grep, and Read tools
- Understand the current state, architecture, and constraints
- Identify the root cause (if debugging) or core requirements (if building)
- Collect relevant file paths and code snippets for partner model consumption

**Step 1.2 -- Systematic deep analysis:**
Use `mcp__pal__thinkdeep` (for debugging/investigation) or `mcp__pal__analyze` (for architecture/feature analysis) to perform structured multi-step investigation. Pass `relevant_files` with absolute paths to all pertinent source files. Set model to `gemini-3.1-pro-preview`.

**Step 1.3 -- Multi-model consensus on findings:**
Use `mcp__pal__consensus` to gather perspectives from both partner models:

```
models: [
  {"model": "gpt-5.5-pro", "stance": "neutral"},
  {"model": "gemini-3.1-pro-preview", "stance": "neutral"}
]
```

The consensus step 1 prompt must present:
- The problem statement
- Your investigation findings from steps 1.1 and 1.2
- Specific questions: what aspects were missed, alternative root causes or approaches, additional constraints or risks

**Step 1.4 -- Synthesize the research brief:**
Combine analysis with consensus output into a research brief containing:
- Problem statement and context
- Root cause analysis or requirements analysis
- Key constraints and risks
- Areas of agreement and disagreement across models
- Recommendations for the planning phase

Hold the research brief in context for Phase 2.

---

### Phase 2: Strategic Planning

Create a detailed execution plan validated across all three models.

**Step 2.1 -- Draft the plan:**
Based on the Phase 1 research brief, create a structured plan covering:
- Specific files to create, modify, or delete (with descriptions of each change)
- Order of operations and dependencies between changes
- Test strategy: which tests to run, what to verify, expected outcomes
- Rollback approach if changes break existing functionality

**Step 2.2 -- Validate with multi-model consensus:**
Use `mcp__pal__consensus`:

```
models: [
  {"model": "gpt-5.5-pro", "stance": "neutral"},
  {"model": "gemini-3.1-pro-preview", "stance": "neutral"}
]
```

The consensus step 1 prompt must present the full plan and ask each model to:
- Identify gaps, missing steps, or overlooked dependencies
- Flag potential risks, edge cases, or failure modes
- Suggest improvements or alternative approaches
- Rate confidence in the plan's completeness (1-10)

**Step 2.3 -- Refine the plan** based on consensus feedback. Address every concern raised or explicitly document why a suggestion was not incorporated.

**Step 2.4 -- Present the plan to the user for approval.**
Display the final plan clearly and wait for explicit user approval before proceeding. If the user requests changes, iterate (repeating consensus validation if changes are substantial). Do NOT proceed to Phase 3 without approval.

---

### Phase 3: Execution

Spawn a agent to execute the approved plan.

**Step 3.1 -- Capture pre-execution state:**
Run `git stash list && git status && git log --oneline -5` to record the
baseline state before execution begins.

**Step 3.2 -- Spawn the executor:**
Use the Task tool:

```
subagent_type: "general-purpose"
mode: "bypassPermissions"
```

The Task prompt must include:
1. The complete approved plan from Phase 2 (verbatim)
2. Clear instruction to execute each step in the specified order
3. Instruction to run the specified tests after making changes
4. Instruction to report back with:
   - Summary of every file changed and what was done
   - Full test output (pass/fail for each test)
   - Any deviations from the plan and why they were necessary
   - Any issues, warnings, or concerns encountered during execution

**Step 3.3 -- Collect results:**
When the agent completes, capture its full report. Run `git diff` to independently verify what changed. Hold both the agent report and the diff in context for Phase 4.

---

### Phase 4: Comprehensive Review

Perform thorough review of all changes made during execution.

**Step 4.1 -- Gather the diff:**
Run `git diff` (or `git diff HEAD~N..HEAD` if changes were committed) to capture all modifications. Also run any tests specified in the plan to independently verify results.

**Step 4.2 -- Structured code review:**
Use `mcp__pal__codereview` for systematic review:
- Set `model` to `gemini-3.1-pro-preview`
- Set `review_type` to `full`
- Include the diff via `relevant_files` (pass the changed file paths)
- In the step narrative, cover: correctness, security, performance, architecture, and test coverage

**Step 4.3 -- Multi-model review consensus:**
Use `mcp__pal__consensus`:

```
models: [
  {"model": "gpt-5.5-pro", "stance": "neutral"},
  {"model": "gemini-3.1-pro-preview", "stance": "neutral"}
]
```

The consensus step 1 prompt must include:
- The full diff of changes
- The executor's report (deviations, test results)
- The Phase 2 plan for comparison
- Ask each model to evaluate:
  - Correctness of the implementation
  - Security vulnerabilities (OWASP top 10)
  - Performance implications
  - Whether changes match the plan and original intent
  - Regressions or unintended side effects
  - Test coverage adequacy

**Step 4.4 -- Compile review report:**
Synthesize analysis with codereview output and consensus into a review report organized by category (correctness, security, performance, architecture, test coverage). Note severity for each finding.

Hold the review report in context for Phase 5.

---

### Phase 5: Devil's Advocate Critique

Apply aggressive critical analysis to find problems the review missed.

**Step 5.1 -- Adversarial self-analysis:**
Deliberately adopt a hostile critic's perspective. Assume the code has hidden bugs, the review was too lenient, and important edge cases were missed.

Examine:
- Every conditional branch: what if the other path is taken?
- Every external call: what if it fails, times out, or returns unexpected data?
- Every assumption: what if it's wrong?
- Concurrency: are there race conditions or deadlocks?
- Error propagation: are errors swallowed or mishandled?
- The review itself: did reviewers agree too readily? What did they not check?

**Step 5.2 -- Adversarial multi-model consensus:**
Use `mcp__pal__consensus` with adversarial stances:

```
models: [
  {
    "model": "gpt-5.5-pro",
    "stance": "against",
    "stance_prompt": "You are a hostile code reviewer. Find every possible
      flaw, vulnerability, edge case, race condition, and design mistake in
      these changes. Be ruthlessly critical. If you cannot find real problems,
      identify theoretical risks and worst-case scenarios. Also critique the
      review report -- what did the reviewers miss or dismiss too easily?"
  },
  {
    "model": "gemini-3.1-pro-preview",
    "stance": "against",
    "stance_prompt": "You are a security auditor and reliability engineer.
      Assume this code will be attacked by adversaries and subjected to
      extreme load. Find every weakness, every assumption that could fail,
      every error path that is not handled. Question the architectural
      decisions. Challenge the test coverage. Also examine the review report
      for blind spots and groupthink."
  }
]
```

Include both the diff and the Phase 4 review report in the consensus step 1 prompt.

**Step 5.3 -- Synthesize critique:**
Compile all adversarial findings into a critique report categorized by severity:
- **Critical**: Must fix before merging; functional bugs, security holes, data corruption risks
- **High**: Should fix soon; significant quality or reliability concerns
- **Medium**: Worth addressing; maintainability, robustness improvements
- **Low**: Nitpicks and theoretical concerns for awareness

---

### Phase 6: Final Report & Remediation

Present the complete results to the user.

**Step 6.1 -- Summary report:**
Present a concise report covering:
1. **Problem** (1-2 sentences from Phase 1)
2. **Approach** (key decisions from Phase 2)
3. **Changes made** (file list and summary from Phase 3)
4. **Review findings** (highlights from Phase 4, by category)
5. **Devil's advocate findings** (Phase 5 critique, by severity)
6. **Overall assessment**: ready to merge, needs fixes, or needs rework

**Step 6.2 -- Remediation (if critical issues found):**
If Phase 5 produced critical findings:
- Present them clearly with specific remediation recommendations
- Ask the user whether to fix now or defer
- If the user requests fixes: create a targeted remediation plan, loop back to Phase 3 (execution) with only the fixes, then repeat Phases 4-5 on the remediation changes only

**Step 6.3 -- Completion:**
If no critical issues remain, confirm the implementation is ready and note any medium/low concerns for the user's awareness.

## PAL Model Reference

| Role | PAL Model Name | Used In |
|------|---------------|---------|
| Orchestrator | (native Opus or Fable) | All phases |
| Partner 1 | `gpt-5.5-pro` | Consensus in Phases 1, 2, 4, 5 |
| Partner 2 | `gemini-3.1-pro-preview` | Consensus + codereview in Phases 1, 2, 4, 5 |
| Executor | `fable` or `opus` (Task tool model param) | Phase 3 only |

## Constraints

- Never skip phases. The pipeline's value comes from the full sequence.
- Never proceed from Phase 2 to Phase 3 without explicit user plan approval.
- Phase 3 must use only the strongest model.
- Phases 1, 2, 4, and 5 must use the strongest model with PAL consensus (analytical rigor).
- Keep intermediate artifacts in context; do not write temporary files unless context size demands it.
- Present only the Phase 6 summary to the user; do not expose raw consensus outputs or intermediate phase artifacts unless the user asks for them.
- If any phase encounters an unrecoverable error, halt and report to the user with context about what succeeded and what failed.
