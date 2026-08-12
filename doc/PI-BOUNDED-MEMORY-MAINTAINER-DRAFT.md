# Pi retained session history grows live memory

Local, unpublished maintainer draft. Posting or maintainer contact requires
separate authority. John must rewrite and review the exact final issue bytes in
his own voice. Post only through the Contribution Proposal template with
`pkg:agent` and `pkg:coding-agent` labels.

## Issue draft

**Title:** Make retained session memory independent of persisted history

### What do you want to change?

Make normal coding-agent execution retain bounded history through Pi's v4
repository seam. Before code, please choose:

1. direct AgentHarness adoption or a temporary `SessionRepo` adapter; canonical
   SQLite or indexed JSONL;
2. reversible v1-v3 import preserving topology and opaque data; required Node,
   Bun, OS, and filesystem support;
3. item and byte admission, session- and generation-bound cursors, stale and
   oversized results, cancellable exact scans, and backpressure;
4. replacement, close, cancellation, and lease ownership; bounded versioned
   hook/RPC payloads or an explicitly unbounded administrative path;
5. a bounded ephemeral repository for `--no-session` and pre-publication state,
   or a hard admission boundary and explicit exclusion;
6. compatibility duration and exit condition; eager materializer removal from
   strict default or an operator-enabled administrative capability; and
7. this claim: for fixed active context, configured budgets and concurrency,
   and reviewed topology, source-reviewable Pi-owned live history on normal
   paths does not grow with total persisted history bytes or entries.
   Whole-history administration, opaque runtime and allocator state, and
   uncertified extensions remain outside it.

### Why?

Classic coding-agent retains every JSONL record in `fileEntries` and every
non-header session entry in `byId` after compaction selects a small context. In
upstream 0.84.1, a fixed tail and workload used about 103 MB raw RSS at 16 MiB
history and 1.28 GB at 1 GiB. This is descriptive, not a threshold.

### How? (optional)

I intend to implement the first approved step as one small PR for bounded reads,
stable cursors, cancellation, and oversized-record results. Keep import,
adoption, migration, and strict cleanup separate. A downstream prototype
supplies tests, not an upstream patch.
