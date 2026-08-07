# validated-code-review

A Claude Code skill that runs a multi-model, multi-stage code review of the current branch before a pull request goes up for human review. Independent review agents scan the diff in parallel, a different model verifies every claim against the actual code, a consensus forum of all the models settles the disputed calls, and the result is a single distilled document that leads with merge blockers.

The review is strictly read-only. No agent in the pipeline builds the project or runs tests. Every claim must be supported by citing code.

## Contents

1. [Quick start](#1-quick-start)
2. [Pipeline at a glance](#2-pipeline-at-a-glance)
3. [Stage by stage](#3-stage-by-stage)
4. [Design rationale](#4-design-rationale)
   1. [Subagents for context control](#41-subagents-for-context-control)
   2. [clink for cross-model dispatch](#42-clink-for-cross-model-dispatch)
   3. [Consensus as the arbiter](#43-consensus-as-the-arbiter)
5. [Inputs and configuration](#5-inputs-and-configuration)
6. [Output](#6-output)
7. [Repository layout](#7-repository-layout)
8. [Installation](#8-installation)
9. [Requirements](#9-requirements)

## 1. Quick start

From a Claude Code session on the branch you want reviewed, ask for a validated review. The word "validated" is the trigger:

```
run a validated code review
```

Common variations:

```
run a validated code review against origin/feature-part-1
run a validated code review, add a concurrency category
run a validated code review with claude-fable-5 and gpt-5.6-sol
```

The review takes a while because it launches many agents. When it finishes, read `<branch>-code-review.md` in the repository root.

## 2. Pipeline at a glance

The diagram below shows one simulated run with the default two-model list. Each focused reviewer's model is drawn at random, and every review is verified by a model other than the one that wrote it, which is why each reviewer and verifier pair shows opposing colors.

![Pipeline stages](assets/validated-code-review-stages.svg)

The source for this diagram is `assets/validated-code-review-stages.dot`. Regenerate the SVG after editing it:

```bash
dot -Tsvg assets/validated-code-review-stages.dot -o assets/validated-code-review-stages.svg
```

## 3. Stage by stage

| Stage | Name | What happens |
|-------|------|--------------|
| 0 | Setup | Fetch the remote, diff the branch against the base ref, and stage all inputs in a scratch directory. |
| 1 | Independent reviews | Focused reviewers (correctness, memory safety, comment quality, test coverage, plus any user extras) and one broad reviewer per model all run in parallel. Each writes its own claims file. |
| 2 | Verification | Every review file is checked claim by claim against the real code by a different model. Surviving claims are graded P0 through P2. |
| 3 | Consolidation | Invalid claims are dropped, duplicates are merged at the highest severity, and every claim is annotated with its reviewer, verifier, and verification outcome. |
| 4 | Consensus forum | All models in the list deliberate together over the consolidated review and confirm or reject each P0 and P1 as a genuine merge blocker. |
| 5 | Synthesis | The confirmed findings become one document: P0 merge blockers first, P1 follow-ups next, vetted P2 nits last. Each finding carries a file and line reference, evidence, and a suggested fix. |

The severity scale is simple. P0 means the branch must not merge until the issue is fixed. P1 means the issue is real but not blocking. P2 covers minor and stylistic points.

## 4. Design rationale

Three decisions shape this skill: reviews run in subagents, non-Claude models are driven through their own CLIs, and disputed claims are settled by a consensus forum rather than by the orchestrator.

### 4.1 Subagents for context control

The orchestrating session never reads the diff or the source tree itself. Every reviewer and every verifier runs in its own subagent with a fresh context window, reads whatever files it needs at full depth, and writes a compact markdown report to the scratch directory. Only the report files flow back to the orchestrator.

This matters for two reasons. First, context economy: a thorough review of a large diff can consume hundreds of thousands of tokens of file reads, and with seven or more reviewers running in parallel, no single context window could hold all of that work. Isolating each reviewer means each one gets a full window for deep reading while the orchestrator stays small and can manage the whole pipeline from start to finish. Second, independence: reviewers cannot see each other's claims, so when two reviewers find the same issue, that agreement is real signal rather than an echo. The tinted stages in the diagram mark exactly which parts of the pipeline run in this isolated fashion.

### 4.2 clink for cross-model dispatch

Claude Code's Agent tool can only spawn Claude subagents. To get genuinely different models into the pipeline, the skill uses `clink` (CLI link) from the PAL MCP server, which drives other vendors' models through their own command line tools, such as the codex CLI for GPT models. Each clink invocation is its own out-of-process session, so a clink reviewer gets the same context isolation as a Claude subagent. When clink is unavailable, the skill falls back to PAL's `chat` tool with the same model.

Cross-model diversity is the point of the whole design. Different model families have different blind spots, and a single model verifying its own claims tends to agree with itself. The skill therefore enforces one hard rule: no review is ever verified by the model that wrote it. A claim that one model raised and a different model family confirmed against the code has survived a much stronger filter than either model could provide alone.

### 4.3 Consensus as the arbiter

Verification in Stage 2 is mechanical: a claim either matches the code or it does not. What remains after consolidation is the judgment layer. Whether a confirmed issue truly blocks a merge, or whether a P1 deserves promotion or demotion, is not something a single verifier should decide.

Stage 4 hands these judgment calls to PAL's `consensus` tool, which convenes every model in the list over the same evidence: the consolidated claims, the diff, the relevant source context, and the annotations showing who reviewed and who verified each claim. Unlike the earlier stages, where isolation is deliberate, this stage wants the models deliberating together, because severity is a question of weighing tradeoffs rather than checking facts. The forum runs out of process like everything else, so only the verdicts return to the orchestrator. Claims the forum rejects as spurious or trivial are cut during synthesis.

## 5. Inputs and configuration

All configuration is conversational. State overrides in the same message that requests the review.

| Input | Default | Notes |
|-------|---------|-------|
| Model list | The `MODELS:` line at the top of `SKILL.md` | The list must contain at least two models, because different-model verification is impossible with one. Add or substitute models of comparable strength. |
| Base ref | `origin/main` | Set this to the parent branch when reviewing one PR in a stack, for example `origin/feature-part-1`. Otherwise the diff would include the parent PRs' changes. Prefer remote tracking refs. |
| Extra categories | None | Additional focused review categories beyond the four defaults, for example concurrency or API compatibility. |

To change the default model list for your whole team, edit the `MODELS:` line in `SKILL.md`.

## 6. Output

The final review is written to two places:

- `<branch>-code-review.md` in the repository root. This is the deliverable. The skill never commits it, because posting the review is the reviewer's job.
- `/tmp/code-review-<branch>-<sha>/` holds every intermediate artifact: the diff, the per-category review files, the verification files with reviewer and verifier recorded, the consolidated review, and the final document. Consult these when you want to see how a finding was reached or what was cut.

## 7. Repository layout

```
validated-code-review/
├── README.md
├── SKILL.md
└── assets/
    ├── validated-code-review-stages.dot
    └── validated-code-review-stages.svg
```

`SKILL.md` is the operative file. Everything the agent does, including the stage instructions, the model assignment rules, and the hard constraints, lives there. This README documents the design for people and is never loaded by the agent, so behavior changes belong in `SKILL.md` and explanation changes belong here. The `assets` directory holds the Graphviz source for the pipeline diagram and the rendered SVG that is embedded above.

## 8. Installation

Copy this directory into your Claude Code skills directory. The folder name must match the skill name:

```bash
cp -r . ~/.claude/skills/validated-code-review
```

Start a new Claude Code session and the skill appears in the available skills list. Trigger it as shown in the quick start.

## 9. Requirements

- An agentic environment with subagent support (the Agent tool in Claude
  Code; the native subagent mechanism elsewhere).
- The [PAL MCP server](https://github.com/positron-mark/pal-mcp-server) connected, providing the `clink`, `chat`, and `consensus` tools.
- CLI access for each non-Claude model in the list, for example the codex CLI for GPT models, with credentials configured.
- Graphviz (`dot`), only if you want to regenerate the diagram.
