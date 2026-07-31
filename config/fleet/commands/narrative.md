Create a human-oriented design narrative for the development work described by
the user's request and any `$ARGUMENTS`.

The narrative should tell the story of the work: what problem was being solved,
what the AI agent had to discover, where the path was more difficult than it
first appeared, how those difficulties were overcome, which principles emerged,
and what understanding the finished work now preserves. It should not read like
a changelog, commit summary, or technical postmortem. It should give a thoughtful
reader a clear sense of the journey without drowning them in implementation
detail.

Use the available evidence. In particular:

- Read the journal file named in the request or arguments. If no journal file is
  named, search the project for likely journal files and choose the one most
  clearly tied to the current work. If there is no clear candidate, ask for the
  journal path before writing the narrative.
- Read the journal preface first. Then read the entries that bear on the work,
  especially the most recent entries and any entries tagged as design,
  verification, architecture, failure, recovery, constraints, or lessons.
- Inspect the git history under consideration. If the request gives a commit
  range, branch, PR, or set of commits, use that scope. Otherwise, infer the
  current branch's work from the local git state, upstream branch, recent commits,
  and working-tree changes.
- Inspect the working tree itself: `git status`, relevant diffs, and the files
  that embody the feature. Do not rely on commit messages alone.
- Read any planning, design, specification, handoff, or task documents created
  during the work. Prefer documents whose paths, titles, timestamps, or content
  connect them to the journal and commits.
- Use tests, build output, review notes, and verification artifacts as evidence
  for what was finally proven, but do not turn the narrative into a test report.

Before drafting, also study the prose standard in
`~/work/positron/it-plan.pdf`, if it is readable in the current environment. Use
it only as a standard for tone, movement, and English usage, not as a source of
content. If the PDF is unavailable, state that briefly and apply the embedded
style standard below.

Style standard:

- Write in calm, measured English. The voice should be humane, practical, and
  dignified, with confidence that does not overstate the evidence.
- Begin with the purpose and governing principles before turning to the concrete
  course of events. Let practical consequences flow from those principles.
- Prefer clear paragraphs with modest headings. Use bullets only when they serve
  the reader better than prose, and keep them sparse.
- Use transitions that show how one discovery led to the next. The reader should
  feel the work unfolding, not merely being listed.
- Keep technical particulars in service of the story. Name important mechanisms
  when they matter, but avoid implementation minutiae unless they illuminate a
  choice, constraint, or turning point.
- Distinguish fact from inference. If a source does not prove a claim, either
  leave the claim out or phrase it as an interpretation grounded in the evidence.
- Avoid self-congratulation, marketing language, theatrical language, and false
  drama. Let the difficulty of the work appear through the constraints, failed
  assumptions, and eventual shape of the solution.
- Do not copy phrasing or content from the style-reference PDF. Imitate the
  standard of English, not the subject matter.

Recommended working method:

1. Establish the scope: journal path, commit range or branch, relevant working
   tree state, and supporting planning/design/handoff documents.
2. Build a compact chronology from the journal, commits, diffs, and handoff
   material. Identify the few moments that changed the agent's understanding.
3. Extract the durable themes: constraints discovered, design principles
   clarified, mistakes corrected, verification lessons, and the final shape of
   the work.
4. Draft the narrative as a polished Markdown document. A useful shape is:
   `Title`, `Purpose`, `How the Work Unfolded`, `What Had to Be Learned`,
   `How the Difficulties Were Resolved`, `Principles Preserved`, and `Where the
   Work Now Stands`. Adjust headings to suit the material.
5. End with a short source note naming the journal, commit range, working-tree
   state, and major planning or handoff documents consulted. Keep the source note
   factual and compact.

If the user provides an output path in `$ARGUMENTS`, write the narrative there.
Otherwise, present the narrative directly in the response. If you cannot gather
enough evidence to write responsibly, stop and say exactly what source is missing.
