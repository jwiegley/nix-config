Bring my entire Graphite PR stack up to date with `main`, resolving every
conflict encountered along the way, and submit the result. Run every `gt`
command with `GIT_EDITOR=true` so nothing blocks waiting on an editor.

See also: the resolve workflow is the canonical conflict-resolution step -- step
4 below resolves each conflict the way resolve directs.

1. Record the starting state before touching anything: capture `gt ls` and
   each stack branch's tip SHA (`git rev-parse <branch>`) so the final report
   can prove nothing was lost in the rewrite.
2. Run `gt get` to sync trunk and the stack from the remote.
3. Run `gt restack`.
4. If a conflict is encountered, resolve it the way the resolve command
   directs: identify which commit is being applied onto which branch, analyze
   the diff3 three-way (HEAD vs parent-of-commit vs incoming commit), and
   produce a resolution that preserves the semantics of the incoming change
   while maintaining the intent of the already-restacked work. Use haskell-pro
   for Haskell conflicts and cpp-pro for C++ conflicts; trivial comment-only
   conflicts may be resolved directly. When each side added something
   orthogonal (a parameter, a field, a clause), combine both sides rather than
   picking one.
5. Verify every resolution before moving on: zero conflict markers remain, the
   affected code builds, and the relevant unit tests pass (e.g.
   `bin/ingest-cabal build && bin/ingest-cabal test` for ingest Haskell
   changes). Then `git add` the resolved files -- never commit manually and
   never run `git rebase --continue` directly.
6. Run `gt continue`, and repeat steps 4-6 for every further conflict, through
   every branch in the stack.
7. When the restack completes, check `gt ls`: if any stack branch still shows
   "needs restack" (main moved during the run), return to step 2 -- git rerere
   replays the earlier resolutions automatically.
8. When the whole stack is clean and up to date with main, run
   `gt submit --stack`.
9. Finish with a complete summary of the entire run: every conflict
   encountered (branch, commit, files), how each was resolved and verified,
   and evidence that no meaningful changes were lost or broken -- run
   `git range-diff` between each branch's recorded pre-restack tip and its new
   tip and confirm only the expected adjustments appear.
