# Portable-Subflake Rename Rollback

`config/fleet` is the real portable subflake. `config/ai/flake.nix` is an
intentional throwing stub. This runbook remains relevant only while maintained
external consumers still carry a paired legacy `dir=config/ai` input.

## Rules

- Treat `test/inventory/consumer-inventory.json` as the consumer-edge inventory;
  regenerate it before relying on paths or line numbers.
- Inspect both repository remotes. A recovery is incomplete if they disagree.
- Preserve each consumer's existing URL and pin style unless a separate explicit
  action changes that policy.
- Change the root and portable lock nodes together at one revision.
- Re-lock as the regular user; only activation uses root.
- Publication, consumer edits, and activation are independent authorized actions.
- Never force-push or rewrite shared history for this recovery.

## Detect the current state

```bash
test/bin/consumer-inventory --print > /tmp/nix-consumer-inventory.json
bin/publish                     # preflight only; does not publish
git log --oneline --decorate --all -- config/ai config/fleet
```

Then inspect each authoritative consumer lock without activating it. Classify the
incident before acting:

1. rename exists only in an unpublished local branch;
2. one repository remote has the rename;
3. both remotes have it and no consumer lock advanced;
4. one or more consumer locks advanced; or
5. a consumer activated the renamed revision.

If any remote or authoritative consumer is unreachable, state detection is
incomplete and recovery stops.

## Recovery

### Unpublished branch

Abandon or revert the local branch normally. Do not touch remotes or consumers.

### Remote disagreement

Identify a signed revision already present on the authoritative remote and reconcile
the other remote with a fast-forward publication. `bin/publish --publish` is the
only repository publication path and requires explicit authorization.

### Consumers have not advanced

Reconcile both remotes. No consumer edit or activation is needed.

### Consumer locks advanced

For each affected consumer, in its authoritative checkout:

1. restore the paired URL to the last known-good portable path;
2. point both root and portable inputs at the same signed revision;
3. regenerate the lock as the regular user;
4. verify the lock is byte-stable under a read-only evaluation; and
5. run the consumer's build without activation.

Use `test/bin/cross-consumer-eval` from this repository to check the maintained
reach-in consumer set against the candidate source. Use the `portable-eval`
quality suite for consumers such as Vulcan that use the supported flake
interfaces.

### A consumer activated

First restore the consumer's previous generation using its native rollback
mechanism. Keep the previous closure rooted until runtime acceptance succeeds. Then
repair its checkout and locks as above. Shared-work hosts must pre-populate the
candidate closure on every member before any member activates it; see
`doc/ARCHITECTURE.md`.

## Closeout

- both repository remotes name the intended signed revision;
- every maintained consumer has coherent paired lock nodes;
- builds pass in every changed authoritative checkout;
- any activation has an observed rollback path and runtime acceptance; and
- the consumer inventory is regenerated with no unexplained legacy edge.

Once every maintained consumer uses `dir=config/fleet` and the compatibility stub is
retired, delete this runbook.
