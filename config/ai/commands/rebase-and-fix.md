I want to Git rebase the current working tree onto the $ARGUMENTS branch. Use haskell-pro and cpp-pro to analyze and resolve these conflicts in a way that preserves the semantics of the incoming changes, while maintaining the intent of the current working tree's work. Continue until the branch is fully rebased.

See also: the resolve workflow is the canonical conflict-resolution step this follows at each rebase conflict -- preserve the semantics of the incoming change while maintaining the intent of the current work, then `git add` the result.

If there are any other branches between this branch and $ARGUMENTS, I want you to also observe the following:

- use rebasing to update and rewrite all the descendent branches, back to $ARGUMENTS
- make sure the rewritten commits and all descendents become the new HEAD of their respective branches, so that the branch<->commit relationship is preserved despite these rewrites
- force push the rewritten branches (when necessary) so their corresponding PRs are updated

After pushing, wait to see whether any CI tests are failing for this PR. Use the appropriate programming language agent to diagnose and resolve this issue, then push your fixes to the PR and monitor the CI test results using `gh` until you observe that everything passes correctly. If any further problems should be observed, repeat this diagnose, resolve, push and monitor process until everything is working with this PR.

Also, if there are any BugBot, Cursor or Devin comments on this PR, I want you to fix and address these comments from these bots, and then after you have pushed the fixes, I want you to reply to those comments and then mark them resolved.
