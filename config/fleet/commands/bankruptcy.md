The number of commits in this branch has become a little bit ridiculous. I want to do a round of cleanup now, just this one time, that looks like this:

Stash any current work first, to be unstashed after this is done.

- =git remote update=
- =git rebase main= (resolving any conflicts that may arise)
- =git reset --soft main=
- =git reset HEAD=

Now the work of the entire branch is uncommitted in the working tree. At this point, use the `command` skill or $command-commit to re-commit all the work that has happened here, this time in a series of orderly commits that express the logical sequence of the work that has happened thus far.

The end result should be an unchanged working tree, but a new Git commit history that is much more compact and will be much quicker to rebase in the future.
