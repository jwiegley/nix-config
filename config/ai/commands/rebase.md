Think deeply to analyze the following task, construct a well thought out plan of action, and then carefully execute that plan step by step.

See also: the resolve workflow is the canonical conflict-resolution step -- resolve each conflict the way resolve directs (preserve the semantics of the incoming change while maintaining the intent of the current work, then `git add` the result), applied here at every rebase conflict.

I want to Git rebase the current working tree onto the $ARGUMENTS branch. Use haskell-pro to analyze and resolve these conflicts in a way that preserves the semantics of the incoming changes, while maintaining the intent of the current working tree's work. Continue until the branch is fully rebased.

If there are any other branches between this branch and $ARGUMENTS, I want you to also observe the following:

- use rebasing to update and rewrite all the descendent branches, back to $ARGUMENTS
- make sure the rewritten commits and all descendents become the new HEAD of their respective branches, so that the branch<->commit relationship is preserved despite these rewrites
- force push the rewritten branches (when necessary) so their corresponding PRs are updated
