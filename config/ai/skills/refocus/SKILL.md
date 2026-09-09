---
name: refocus
description: Reassess scope creep against the user's goal at least hourly during active work, then refocus on timely completion. Use when asked to refocus or whenever Wiggum is active.
---

# Refocus

Keep the user's goal and completion criteria as the authority for deciding what
to do next. Keep this skill active throughout the task, including continuations
and context compaction.

## When to check

- Refocus immediately when this skill becomes active, then **at least once every
  60 minutes of wall-clock time during active work**. Check sooner when work
  branches into an unplanned investigation, repeated retries, or optional polish.
- Read the current time from an available clock tool or system clock. Record the
  last completed check and the next deadline in the existing task state or
  handoff; do not estimate elapsed time from turns or token counts.
- Check the clock at work-unit boundaries and before and after long tool calls
  or waits. Use bounded waits so a running build or test does not postpone the
  check until it finishes; do not cancel useful work just to refocus.
- On resume or after compaction, re-read this skill and the recorded state and
  refocus before new work. If the timestamp is missing or a clock is unavailable,
  refocus immediately and at every work-unit boundary until timing is available.
  Do not claim the hourly deadline was verified without clock evidence.

## The check

1. Re-read the actual goal statement, the user's latest corrections, and the
   accepted plan and completion criteria. Preserve the full requested outcome.
2. Compare current work and recent changes with that goal. Identify scope creep:
   unrelated cleanup, speculative features, widening investigations, repeated
   checks without new evidence, or polishing beyond the requested result.
   Ask which remaining requirement the current action satisfies or unblocks.
3. Stop pursuing detours that do neither. Briefly record useful unrelated
   findings in the existing tracker if appropriate; do not turn recording them
   into another task. Keep required dependencies, fixes, and verification in
   scope. Do not discard work or lower completion criteria to finish sooner.
4. Choose the shortest sound next step toward an unmet requirement and resume
   it. If every requirement is verified, finish. If progress needs a user
   decision, state the specific blocker using the active workflow's rules.
5. Record the check time, goal, any scope correction, and next step in a few
   lines in the existing task state. Set the next deadline no later than
   60 minutes from this check. Include a brief progress update when the plan
   changes; keep the assessment short enough to support timely completion.

Refocusing does not require renewed permission for already authorized work.
Preserve the user's stop requests and the active workflow's approval boundaries.
