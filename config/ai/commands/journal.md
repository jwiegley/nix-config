Maintain a running learning journal for the current work. Use the user's
request and any `$ARGUMENTS` as the scope for what the journal should explain.

The journal is not a task list, handoff, scratchpad, transcript, or command log.
It exists to preserve the important learning that happens while solving a real
problem: the discoveries, design shifts, constraints, failures that taught
something durable, implementation principles, research findings, and moments
where the system proved too general, too specific, or shaped differently than
expected.

Create or continue a Markdown journal in the current project, preferably near
the task's handoff or planning document when one exists. If no location is
obvious, choose a clear filename in the current working directory and say where
it is.

At the top of a new journal, write a brief preface that defines:

- The scope of the work being observed.
- What kinds of entries are valuable for this task.
- The tag vocabulary to use for entries.
- The rule that journal entries are append-only and timestamped.

After the preface, append entries to the end of the file only. Do not back-edit
existing entries. If earlier understanding changes, append a new entry that
states the correction and what changed. Keep a blank line between entries.

Begin every entry with an absolute timestamp, including timezone when known.
Tag each entry with one or more concise area tags in square brackets. Choose
tags that fit the project being worked on, such as `[api]`, `[cli]`, `[data]`,
`[design]`, `[docs]`, `[export]`, `[ingest]`, `[runtime]`, `[tests]`,
`[verification]`, or more specific local subsystem names.

Each entry should capture the durable lesson in a compact form:

- What was discovered.
- What evidence or failure exposed it.
- What changed in the implementation, plan, or mental model.
- Why this may matter for similar work later.

Do not journal every routine step, command, passing test, or transient thought.
Prefer the gems: the hard-won constraints, surprising couplings, principles,
war stories, and aha moments that someone continuing or reviewing the work
would otherwise miss.

When resuming after a context compaction or a fresh session, re-read this
command, then re-read the journal preface before doing new work. Read the most
recent relevant entries as needed to recover the current understanding, and
continue appending new entries from there.
