Enter autonomous-continuation mode for the current work: keep going, without pausing for confirmation, until the Definition of Done holds -- all planned tasks complete and independently verified, or, if a reference target was named, parity with it achieved -- or until a stop-and-escalate condition requires the human.

Always read the environment you need from the current working tree's direnv. Never use `nix develop` to run commands, and never install dependencies on the fly. If you are blocked on a dependency requirement, stop working and ask for the dependency you need. If it can be added to the Nix environment, then do so, regenerate the environment using `de`, and then re-read the direnv environment and try again.

Follow the `wiggum` skill for the full loop methodology: the Definition of Done and stop-and-escalate criteria; the durable plan/handoff/journal state; baseline re-verification after every context compaction; the work -> commit -> audit -> partner-cleanup -> restack loop; the work-unit (not wall-clock) cadence; subagent fan-out limits via the `parallelize` skill; live-Emacs tooling via the `anvil` skill where the host provides the anvil MCP server; and PAL consensus for significant decisions.

When available, use Anvil via your `anvil` skill as the default for every operation it supports. Check unsaved Emacs buffers before each edit batch; prefer Anvil for file exploration and git queries. Fall back to shell or apply_patch only when required, and briefly state why. Recheck Anvil state before committing.

$ARGUMENTS
