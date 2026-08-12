# Pi retained session history grows live memory

Local, unpublished maintainer draft. Posting or maintainer contact requires
separate authority. The public wording must be reviewed and approved by John.

## Issue draft

**Title:** Make retained session memory independent of persisted history

I've been tracing why a resumed Pi session can retain memory in proportion to
its complete JSONL history even after compaction leaves only a small active
context. Classic coding-agent loads every entry into `fileEntries`, indexes the
same objects in `byId`, and keeps appending to both. Selecting a small branch for
the model does not release the complete session.

I froze unmodified upstream 0.84.1 after observing the same commit at `HEAD` and
`main` on August 12. With the same active tail and post-open workload, raw RSS
rose from about 103 MB for a 16 MiB history to 1.28 GB for a 1 GiB history. This
is descriptive evidence, not a proposed threshold.

Pi already has a promising seam in its v4 agent work: `SessionStorage`,
`SessionRepo`, `SessionTree`, in-memory and JSONL repositories, and a separate
SQLite repository package. The current JSONL implementation is also eager, and
classic coding-agent does not use these repositories, but I don't think the
answer is to add a third session architecture beside them. Before preparing
code, could you help choose:

1. the terminal adoption seam;
2. the durable backend and product default;
3. legacy import policy;
4. required runtimes and platforms;
5. the compatibility runway for whole-history APIs;
6. lifecycle ownership and bounded hook and RPC policy;
7. bounded `--no-session` and pre-publication behavior; and
8. exact guarantee wording for reviewed Pi-owned state.

I have a large downstream prototype that breaks the retention chain and contains
useful failure tests, but I don't propose upstreaming it wholesale. If the
direction sounds right, I'd start with a small PR that makes byte- and
item-bounded reads enforceable at the existing repository seam. Legacy import,
coding-agent adoption, consumer migration, and removal of the eager path can
remain separate review boundaries.

I can also share an **AI-assisted supporting packet** containing the exact trace,
immutable evidence, design tradeoffs, and a conditional PR outline. Sharing or
publishing that packet requires separate authority.

## Heads-up draft

I've isolated the retained-history memory issue in classic coding-agent and have
an unpublished issue draft asking where the existing v4 `SessionRepo` work should
meet the classic runtime. I also have exact upstream 0.84.1 evidence and a large
downstream regression corpus, but I'd like maintainer direction before preparing
code. Where would you prefer that design discussion to happen?
