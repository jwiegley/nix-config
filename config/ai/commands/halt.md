Bring the work to a good stopping point so it can be resumed cleanly in a fresh session:

1. Update the handoff document -- what is done, what remains, and exactly how to resume -- so nothing is lost if this machine or session goes away.
2. Commit all outstanding work following the `commit` workflow (a clean, logical commit sequence), then push it.
3. Produce a comprehensive remaining-scope plan and requirements document following the `report` workflow: the full roadmap of work yet to be done, phase by phase, and how completion is to be verified (a succinct, complete target). Instruct that the downstream system run the `fess` skill at the end of every subtask it performs. Write this document to a Markdown file in the `~/dl` directory (create it if it does not exist), not in the project or current directory.
4. Report where things stand and how to resume in another session.
