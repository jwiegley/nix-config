# Parity Oracle Refresh

The fleet parity oracle is the single tracked
`test/baseline/parity-<rev>.json` file produced by
`test/bin/parity-baseline`. It records selected-package multisets and derivation
paths for the maintained targets.

## When to refresh

Refresh only after a parity-affecting change has been accepted:

- `--compare` reports no package-multiset change; or
- every observed package addition/removal has a written explanation.

Do not refresh merely to make a comparison green. Ordinary commits use the cheap
currency guard in `test/bin/oracle-currency-test.py`; deriving the oracle requires
cross-system Nix evaluation and belongs at issue/work-unit closeout.

## Procedure

```bash
old=$(printf '%s\n' test/baseline/parity-*.json)

# Inspect current drift first.
test/bin/parity-baseline --compare "$old"

# No multiset change:
REFRESH_REASON="accepted parity-affecting change" \
  test/bin/parity-baseline --refresh "$old"

# Explained multiset change:
REFRESH_REASON="accepted package-selection change" \
REFRESH_DELTAS=$'lost darwin/clio: example\ngained darwin/hera: replacement' \
  test/bin/parity-baseline --refresh "$old"

git add -A test/baseline/
```

`--refresh` refuses a non-ancestor oracle, command drift, malformed provenance, or
an unexplained multiset change. It appends the reason, intended deltas, and measured
deltas, removes the superseded artifact, and leaves Git as the archive.

## Cheap enforcement

`test/bin/oracle-currency-test.py` checks that:

- exactly one oracle exists;
- its filename, revision, schema, commands, counts, and history agree;
- its revision exists and is an ancestor of the current branch; and
- derivation commands use `--no-write-lock-file`.

These checks establish currency and internal consistency. They do not replace an
expensive `--compare` or `--check` when package parity is part of the acceptance
criteria.

Rollback is an ordinary signed revert of the artifact refresh; it does not alter
host state.
