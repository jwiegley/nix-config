# Verification policy

The test tree establishes properties that remain meaningful when the
configuration is edited by hand. Its principal subjects are evaluation, build
construction, schema and parser validity, security boundaries, transactional
safety, and observable runtime behavior.

Tests must not reproduce the configuration as a second authority. In
particular, do not add:

- committed snapshots of current host values;
- complete package, profile, provider, extension, service, or file rosters;
- assertions about source spelling, comments, formatting, import order, or file
  ownership when the evaluated result is what matters;
- selectors that repeat test class or method names in another file;
- historical issue-specific inventories after a migration is complete.

Literal values remain appropriate when the literal is itself a durable
interface or safety boundary: a protocol fixture, an ABI value, a trusted
signing identity, a forbidden credential form, or a required public output.
Such checks should normally require only explicit removal or incompatible
change; additive configuration should not force their revision.

The ordinary gate remains bounded. Full integration, cross-consumer evaluation,
native builds, and affected-host runtime acceptance belong at issue closeout or
on the scheduled assurance cadence.
