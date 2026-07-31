# RENAME-ROLLBACK — dual-remote rollback of `config/ai` → `config/fleet`

Authored for [jwiegley/nix-config#26](https://github.com/jwiegley/nix-config/issues/26)
(GAP-RENAME-ROLLBACK). It must exist and be committed **before** the rename in
[#47](https://github.com/jwiegley/nix-config/issues/47) lands, because that rename
crosses three consumers and two remotes and there is otherwise no written way back.

This is the recovery runbook only. **Authoring it needs no authorization. Executing
it does:** the re-publish is AG-DUALPUSH (canonical definition on #18), and each
consumer push is AG-PUSH-CONSUMER (explicit, per consumer). No step here authorizes
any system or Home Manager activation; where a rollback reaches activation
(State E) the activation itself is a separate, explicitly-gated action.

---

## 0. The one fact this whole runbook is built on

**A rename that has been published cannot be un-published.** Removing it from a
remote would require rewriting published history — a force-push — which is forbidden
by `CLAUDE.md` and refused outright by `bin/publish`. Therefore **every rollback here
is forward**: a reverse-revert of the complete rename range, re-published to both remotes, plus a
revert of each consumer's URL on its own remote. Nothing is ever rewound. Both remotes
end carrying the rename **and** its revert in history; the *tree* they resolve is
`config/ai` again, but the commit that introduced the stub is not deleted — it is
superseded.

A runbook that said "revert the commit and push" would be worthless. The value below
is entirely in (a) detecting **which of five states** you are actually in, with a
command rather than a guess, and (b) the per-consumer, per-remote divergence once a
consumer has bumped or activated.

---

## 1. Vocabulary, remotes, consumers

### The rename range and its forward revert

| Name | What it is |
|---|---|
| `RENAME_BASE` | The first implementation commit from #47: the commit that moves `config/ai`→`config/fleet`, adds the throwing stub, moves the committed lock, and rewrites the initial internal references. |
| `RENAME_TIP` | The last signed #47 preparation/evidence commit that is published. The complete rollback range is `RENAME_BASE^..RENAME_TIP`, excluding commits that touch only this runbook. Remote/state ancestry tests key off this tip. |
| `REVERT_REV` | The **new**, single signed commit produced by reverse-reverting every implementation/evidence commit in that range, newest first. It restores the pre-rename tree and authorities in one forward commit. This is what you publish. |

Capture `RENAME_BASE` and `RENAME_TIP` the moment #47 lands and record both in the
#26 / #47 issue thread. Everything downstream keys off that immutable range.

### The two remotes — not interchangeable

`bin/publish` names them exactly:

```
origin   gitea@gitea:johnw/nix-config.git         LAN-only; vulcan's ONLY path
github   git@github.com:jwiegley/nix-config.git    vps and the four work machines
```

A revision on one remote is **invisible** to hosts reading the other. This is the
whole reason a partial publish is a first-class state below (State B).

### The three consumer edges (from the committed inventory)

Source of truth: `test/inventory/consumer-inventory.json`
(`repoHead` is read from that generated artifact), classification `stub-covered` — the exact set of ten external
edges the rename touches. There are three consumers behind those ten edges. **Only the
`nix-config-ai` subflake input carries `?dir=config/ai`; the rollback changes no other
URL.** The paired repo-root `nix-config` (`flake = false`) URL stays unchanged, but both
lock nodes must be advanced to the same rollback revision. In particular the
`overlays/*.nix` reach-ins point at the tree root, not at `config/ai`, and are
`retain-with-owner` / `retire` class — untouched by this rollback.

| Consumer | Remote | `nix-config-ai` URL (the line to revert) | Pre-rename locked rev | Checkout read here | Authoritative build tree |
|---|---|---|---|---|---|
| **vulcan** | **gitea** (`origin`) | `nixos/flake.nix:54` `git+ssh://gitea/johnw/nix-config?dir=config/ai` — **FLOATING** (no `?ref`, no `?rev`) | `77b2fc81…` | `~/src/nixos` | `/etc/nixos` on vulcan |
| **vps** | **github** | `vps/flake.nix:20` `github:jwiegley/nix-config?dir=config/ai&ref=main` | `e0ed94fa…` | `~/src/vps` | `/etc/nixos` on ovh-vps |
| **shared-work** | **github** | `andoria/flake.nix:31` `github:jwiegley/nix-config?dir=config/ai&ref=main` | `269b518e…` | `~/src/andoria` (**PROXY**) | `~/.config/home-manager` on andoria-08 / andoria-t2 / delphi-3bd4 / gpu-server — **one shared NFS `$HOME`, one profile symlink** |

Three things about this table drive the rest of the runbook:

- **vulcan is the only gitea consumer, and its URL is floating while its committed lock is exact.** Preserve that URL policy during rollback. Adding a `?rev=` pin is the still-unanswered Q7 policy decision in `doc/FLEET-DECISIONS.md`, not an emergency-procedure side effect. Pin only if Q7 has been explicitly decided before execution.
- **`~/src/andoria` is a proxy, not the live tree.** The live shared-work flake is `~/.config/home-manager` on four machines that share one NFS `$HOME` and **one** profile symlink. Any activation there is **group-wide** — you cannot roll back one work machine.
- The `llm-agents.follows = "nix-config-ai/llm-agents"` lines (`nixos/flake.nix:58`, `vps/flake.nix:12`, `andoria/flake.nix:45`) and the `inputs.nix-config-ai.overlays.default` uses (`nixos/flake.nix:164,312`; `vps/flake.nix:76`; `andoria/flake.nix:78`) reference the input **by name**. They do **not** change during rollback — only the `?dir=` in the URL does. Reverting the URL fixes them all at once.

---

## 2. The forbidden fetcher — read this before verifying anything

**Never verify a consumer through `git+file://` (or any local `path:` / `/…` override
of the nix-config input).** Nix treats a local path as *mutable* and silently rewrites
the consumer's lock to match your working tree — a false pass that hides whether the
*published* revision is actually correct. This is recorded in
`doc/FLEET-DESIGN-PLAN.md` §6.2 ("A trap that would have produced a false pass") and is
enforced structurally: `bin/update-overlay-test.py::test_root_inputs_do_not_reference_external_filesystems`
fails the build if `git+file:`/`file:///`/`path:/` ever appears in the root flake or its
lock closure. #47 forbids the scheme in this runbook for the same reason.

Every verification below therefore uses an **immutable fetcher** — a remote flakeref
pinned to a concrete `rev`:

```
# github consumers (vps, shared-work):
github:jwiegley/nix-config?dir=config/ai&rev=<REVERT_REV>
# gitea consumer (vulcan):
git+ssh://gitea/johnw/nix-config?dir=config/ai&rev=<REVERT_REV>
```

A pinned `rev` cannot be silently rewritten, and — because the subflake requires a
committed lock — it resolves the exact published tree or hard-errors. That is the only
honest test of a rollback.

> One caveat that is itself a rollback correctness property: the subflake at
> `config/ai` imports `../../flake-ai.nix` and `../../test/ai/compatibility-check.nix`
> (`config/ai/flake.nix:79-80`). It is only ever consumable as `?dir=` **of the whole
> repo**, never as a standalone fetch of the subtree. Restoring it therefore means
> restoring the whole-tree relationship, which reverting only `RENAME_TIP` does not
> do once #47 has follow-up commits. Reverting the complete
> `RENAME_BASE^..RENAME_TIP` range does. Verify the up-import still resolves (§7,
> "restore" verify).

---

## 3. Pre-flight (always, before touching anything)

```bash
cd ~/src/nix                      # the nix-config working tree (hera/clio)

# 1. Read the inventory — it is the authority on who breaks. Do not re-derive.
python3 - <<'PY'
import json
d = json.load(open("test/inventory/consumer-inventory.json"))
print("inventory repoHead:", d["repoHead"])
for r in d["references"]:
    if r.get("classification") == "stub-covered":
        print(f'  {r["consumer"]:12} {r["file"]}:{r.get("line","?")}  {r.get("kind")}'
              + (f'  rev={r.get("lockedRev","")[:12]}' if r.get("lockedRev") else ""))
PY

# 2. Confirm both remotes exist and are reachable — a rollback that can only reach
#    one remote recreates the exact divergence it is meant to cure. bin/publish
#    (bare) mutates NOTHING; it only reports.
bin/publish                       # pre-flight only; safe; see §6 for how to read it

# 3. Record the complete published #47 range. Everything keys off it.
RENAME_BASE=<first #47 implementation commit sha>
RENAME_TIP=<last #47 preparation/evidence commit sha>
```

If `bin/publish` reports a remote unreachable, **stop**: you are (probably) off the
LAN and cannot touch gitea. Reconnect before doing anything, or you will roll back one
remote and leave the other renamed.

---

## 4. State detection — the decision tree

Run this once. It tells you which of §7's states you are in. It is read-only.

```bash
set -euo pipefail
cd ~/src/nix

# --- Is the rename even applied in THIS working tree? -----------------------
if [ -d config/fleet ] && grep -q 'throw' config/ai/flake.nix 2>/dev/null; then
  echo "rename APPLIED locally (config/fleet exists; config/ai is a stub)"
else
  echo "rename NOT applied locally"
fi

# --- Which remotes carry the rename? ----------------------------------------
git fetch --quiet --multiple origin github
for r in origin github; do
  if git merge-base --is-ancestor "$RENAME_TIP" "refs/remotes/$r/main" 2>/dev/null; then
    echo "$r: HAS the rename"
  else
    echo "$r: does NOT have the rename"
  fi
done

# --- Have consumers bumped past it? Read authoritative locks without Nix. ---
# The local andoria checkout is only a proxy. Read each host's authoritative
# build tree; failure to reach one means state detection is incomplete, so stop.
for spec in \
  'vulcan:vulcan:/etc/nixos/flake.lock' \
  'vps:ovh-vps:/etc/nixos/flake.lock' \
  'shared-work:andoria-08:~/.config/home-manager/flake.lock'
do
  label=${spec%%:*}
  rest=${spec#*:}
  host=${rest%%:*}
  path=${rest#*:}
  echo "== $label ($host:$path) =="
  ssh "$host" "cat $path" | python3 -c '
import json,sys
nodes = json.load(sys.stdin)["nodes"]
for name in ("nix-config", "nix-config-ai"):
    node = nodes[name]
    print("  %-13s dir=%-12s rev=%s" %
          (name, node["original"].get("dir", "<root>"), node["locked"]["rev"]))'
done
```

Read the three blocks together:

| Local | `origin` (gitea) | `github` | Consumer locks | You are in |
|---|---|---|---|---|
| applied | does NOT have | does NOT have | (irrelevant) | **State A** — local only |
| applied | exactly one HAS the rename, the other does not | | (irrelevant) | **State B** — asymmetric / partial |
| applied | HAS | HAS | every consumer still `dir=config/ai` **and** locked below `RENAME_BASE` | **State C** — published, no consumer bumped |
| applied | HAS | HAS | some consumer shows `dir=config/fleet`, or `dir=config/ai` at/after `RENAME_BASE` (the stub is firing) | **State D** — some consumers bumped |
| applied | HAS | HAS | a consumer bumped **and its host switched** to that generation | **State E** — activated |

"below/at-or-after `RENAME_BASE`" means ancestry, not string order. To decide it precisely for
one consumer, fetch that consumer's remote and test:

```bash
# example, vps (github): is its locked rev at-or-past the rename?
( cd ~/src/vps && git fetch --quiet )   # only if you keep a mirror; otherwise use the sha directly
git merge-base --is-ancestor "$RENAME_BASE" <consumer-locked-rev> 2>/dev/null \
  && echo "at-or-past rename (stub territory)" \
  || echo "below rename (still resolves real config/ai)"
```

A consumer that is **still `dir=config/ai` and below `RENAME_BASE`** has not migrated
and never saw the stub — the easy case. A consumer that is **`dir=config/ai` and
at-or-past `RENAME_BASE`** is *already broken* (hitting the throwing stub); rollback is
what fixes it. A consumer at **`dir=config/fleet`** migrated cleanly and rollback must
walk it back.

---

## 5. What the rollback does about the throwing stub

The stub is a `config/ai/flake.nix` that `throw`s a message naming `config/fleet` and
#47. It retains only the `llm-agents` input key used by known consumers' follows
edges, so those consumers reach the actionable outputs throw instead of failing first
on missing lock topology. The stub has no committed lock. It was introduced in
`RENAME_BASE`.

- **Reverse-reverting the complete rename range removes the stub automatically** —
  the accumulated revert deletes the stub and restores `config/ai` to the real
  subflake with its committed lock in one new commit. This is the supported path and
  why §7 uses a range rather than one `git revert`.
- **If you instead move the directory by hand** (`git mv config/fleet config/ai`),
  git will refuse because `config/ai/` already exists (the stub lives there). You must
  first `git rm -r config/ai` (the stub) and only then `git mv config/fleet config/ai`.
  **Forgetting this is the second-way-to-break-it:** you would restore the rename but
  leave the stub shadowing or colliding with the real subflake. Prefer §7a.
- **Do not leave the stub in place "just in case."** With `config/ai` restored as a
  real subflake, a stub at the same path is a contradiction (two `flake.nix` cannot
  occupy one directory). Rollback removes it; the straggler-tracking / stub-retirement
  gate in [#63](https://github.com/jwiegley/nix-config/issues/63) is about the
  *forward* world and does not apply once you have rolled back.

---

## 6. Shared sub-procedure: dual re-publish via `bin/publish`

Used by States B–E. `bin/publish` is the AG-DUALPUSH tool. Use it; do not hand-roll
two `git push`es.

```bash
cd ~/src/nix
bin/publish                       # PRE-FLIGHT: mutates nothing. Reports, per remote,
                                  # "already at X" / "fast-forward to Y" / "would create".
                                  # Reads both remotes, checks fast-forward-only, checks
                                  # every to-be-published commit is signed.
bin/publish --publish             # only after AG-DUALPUSH is granted for THIS action
```

How to read it for rollback:

- It **refuses to force** and **refuses a non-fast-forward** push. Because `REVERT_REV`
  descends from `RENAME_TIP`, publishing it is always a fast-forward on the remote that
  has the full range, and a fast-forward across the complete range plus its revert on
  the remote that does not. The asymmetric State B is handled by the tool's own
  fast-forward logic; you do not push the remotes differently.
- On a **partial publish** it exits non-zero and prints recovery instructions based on
  its readback state. Depending on which step failed, that can be a targeted push for
  the lagging remote or an instruction to inspect/re-run after remote state is known.
  Follow the emitted instructions exactly while AG-DUALPUSH remains in force, then
  re-run `bin/publish` until it says **both remotes at `<REVERT_REV>`**. Do **not**
  "fix" a partial publish by pointing a consumer at the remote that succeeded — that
  is how the remotes drift for weeks.

**Exit condition for the publish:** `bin/publish` (bare) reports both `origin` and
`github` already at `REVERT_REV`.

---

## 7. Shared sub-procedure: restore `config/ai`, revert a consumer, verify it immutably

### 7a. Restore `config/ai` in nix-config (once, before any consumer work)

```bash
cd ~/src/nix
# Accumulate published implementation/evidence commits newest-first. Commits
# touching only this rollback runbook remain in force and are excluded.
while IFS= read -r revision; do
  git revert --no-commit "$revision"
done < <(git rev-list "$RENAME_BASE^..$RENAME_TIP" -- \
  . ':(exclude)doc/RENAME-ROLLBACK.md')
git commit -S -m 'revert(fleet): restore config/ai after rename rollback'
REVERT_REV=$(git rev-parse HEAD)

# Verify the subflake is real again and the whole-tree up-import resolves:
test -f config/ai/flake.lock && ! grep -q 'throw' config/ai/flake.nix && echo "config/ai restored"
nix flake check ./config/ai --all-systems --no-build       # green = real subflake again
bin/cross-consumer-eval                                     # eval-only, --no-write-lock-file;
                                                            # proves the WORKING TREE still
                                                            # evaluates for all three consumers
```

`bin/cross-consumer-eval` is working-tree evidence, not a lock check — it uses
`--override-input` in memory and never writes a consumer lock. It is the fast local
gate that the restored tree still evaluates. The *honest published* check is 7c.

Then dual-publish `REVERT_REV` via §6 **before** touching any consumer — a consumer
URL revert is meaningless until the revision it points at is on the consumer's remote.

### 7b. Revert one consumer's URL, on its own remote, re-locked immutably

Only the `?dir=` on the `nix-config-ai` URL changes. The `follows` and
`overlays.default` lines are untouched.

```bash
# vps (github) — vps/flake.nix:20
cd ~/src/vps
#   github:jwiegley/nix-config?dir=config/fleet&ref=main
# → github:jwiegley/nix-config?dir=config/ai&ref=main
$EDITOR flake.nix
nix flake update nix-config nix-config-ai # advance both paired nodes coherently from github
                                          # legacy Nix: update both inputs explicitly

# shared-work (github) — andoria/flake.nix:31 — SAME edit, in the AUTHORITATIVE tree
#   (~/.config/home-manager on a work machine), NOT the ~/src/andoria proxy.

# vulcan (gitea) — nixos/flake.nix:54 — preserve the existing URL policy
cd ~/src/nixos
#   git+ssh://gitea/johnw/nix-config?dir=config/fleet
# → git+ssh://gitea/johnw/nix-config?dir=config/ai
# Add ?rev=<REVERT_REV> only if Q7 has an explicit recorded "pin" decision.
$EDITOR flake.nix
nix flake update nix-config nix-config-ai
```

Push each consumer change to its **own** remote (vulcan→gitea, vps→github,
shared-work→github) — this is AG-PUSH-CONSUMER, explicit per consumer. vulcan's and
vps's authoritative trees are `/etc/nixos` under `.nixos-build` locking; obey it.

### 7c. Verify each consumer immutably (the only honest check)

```bash
# Prove the RESTORED subflake resolves at the revert rev over the immutable fetcher.
# github consumers:
nix flake metadata --no-write-lock-file \
  "github:jwiegley/nix-config?dir=config/ai&rev=$REVERT_REV" --json \
  | python3 -c 'import json,sys; d=json.load(sys.stdin); print("resolved rev:", d["locked"]["rev"])'
# gitea consumer:
nix flake metadata --no-write-lock-file \
  "git+ssh://gitea/johnw/nix-config?dir=config/ai&rev=$REVERT_REV" --json \
  | python3 -c 'import json,sys; d=json.load(sys.stdin); print("resolved rev:", d["locked"]["rev"])'

# Then, in EACH consumer's authoritative tree, prove both paired lock nodes are
# coherent, at REVERT_REV, and byte-stable under a read-only Nix evaluation:
lock_digest_before=$(nix hash file --type sha256 flake.lock)
nix flake metadata --no-write-lock-file . --json >/dev/null
lock_digest_after=$(nix hash file --type sha256 flake.lock)
test "$lock_digest_before" = "$lock_digest_after" || {
  echo "FAIL: read-only verification changed flake.lock" >&2
  exit 1
}
python3 - "$REVERT_REV" <<'PY'
import json, sys
expected = sys.argv[1]
nodes = json.load(open("flake.lock"))["nodes"]
root = nodes["nix-config"]
fleet = nodes["nix-config-ai"]
assert fleet["original"].get("dir") == "config/ai", fleet["original"]
for name, node in (("nix-config", root), ("nix-config-ai", fleet)):
    locked = node["locked"]
    assert locked.get("type") in ("github", "git"), (name, locked)
    assert "file" not in locked.get("url", ""), (name, locked)
    assert locked.get("rev") == expected, (name, locked.get("rev"), expected)
assert root["locked"]["rev"] == fleet["locked"]["rev"]
print("OK: paired lock nodes at", expected[:12], "and flake.lock is byte-stable")
PY
```

Run that block in `/etc/nixos` on vulcan, `/etc/nixos` on ovh-vps, and
`~/.config/home-manager` on a shared-work host. A URL may remain floating by policy;
the committed lock must not move during verification. **A lock whose paired nodes
disagree, whose `nix-config-ai` node is `type = path`, or which carries a `file://`
URL is a false pass; reject it.**

---

## 8. The five states

### State A — rename committed locally, not published

**Detect:** §4 shows "rename applied locally" but **neither** remote HAS the rename.

**Act:** trivial and backward-safe, because nothing is published, so no history rewrite
is involved.

```bash
cd ~/src/nix
# Use §7a to reverse-revert the complete RENAME_BASE^..RENAME_TIP range.
# If this is still an unmerged feature branch, abandoning that branch is simpler.
```

No consumer touch, no publish. (If you have not yet published anything, you also have
the option of simply not landing #47 — abandon the branch.)

**Verify:** §7a's "config/ai restored" checks pass; `bin/publish` (bare) still shows
both remotes at the pre-rename revision.

---

### State B — published to ONE remote only (the asymmetric case — most likely)

This is the state `bin/publish` explicitly reports and the one most likely to actually
occur: a network fault in the window between the two real pushes leaves, say, `github`
at `RENAME_TIP` while `origin` (gitea) is still pre-rename. The blast radius is
**lopsided**: the consumers on the remote that received the rename (vps + shared-work if
`github`, or vulcan if `origin`) can now hit `config/fleet`/the stub on their next float
or bump; the consumers on the other remote are entirely unaffected.

**Detect:** §4 shows exactly one of `origin`/`github` HAS the rename.

**Act — decide direction first:**

- If the rename is *fine* and you merely want the remotes consistent (roll *forward*,
  not back), just complete the publish: `bin/publish --publish` fast-forwards the
  lagging remote. That is not this runbook's job, but recognize the fork.
- To **roll back**: build `REVERT_REV` (§7a) and dual-publish it (§6). `bin/publish`
  fast-forwards each remote from its current point through the required remaining
  range and the forward revert; both end at `REVERT_REV`. You are **not** un-publishing
  the rename from the remote that got it — that history stays; the tree it resolves is
  `config/ai` again.
- Then handle any consumer on the remote that received the rename exactly as its state
  dictates (usually State C — nobody bumped in the fault window; occasionally D).

**Verify:** `bin/publish` (bare) reports **both** remotes at `REVERT_REV`; §7c passes
for every consumer whose remote carried the rename.

---

### State C — published to both, no consumer has bumped

The rename is on both remotes, but every consumer still locks `dir=config/ai` at a rev
**below** `RENAME_BASE`, so every consumer still resolves the pre-rename tree and none
ever saw the stub. This is the clean forward revert.

**Detect:** §4 shows both remotes HAVE the rename; every consumer block shows
`dir=config/ai` with `rev` below `RENAME_BASE` (ancestry check in §4).

**Act:**
1. §7a — reverse-revert `RENAME_BASE^..RENAME_TIP` into `REVERT_REV`, then §6 dual-publish.
2. That is enough for the two `&ref=main` github consumers (vps, shared-work) and the
   floating gitea consumer (vulcan) to land back on `config/ai` at their **next**
   `nix flake update` — because their URLs still say `dir=config/ai` and the tree at
   `REVERT_REV` has `config/ai` again.
3. **Optional, recommended:** proactively re-lock each consumer now (§7b's
   `nix flake update nix-config nix-config-ai` in each authoritative tree) so the
   paired nodes advance coherently. Preserve Vulcan's current floating URL unless Q7
   has an explicit recorded decision to add a `rev` pin.

**Verify:** for an untouched consumer, parse its committed lock directly and require
both paired nodes to remain equal at the same pre-`RENAME_BASE` revision. If step 3
re-locked it, run §7c and require both nodes at `REVERT_REV`. In both cases the
immutable restored-subflake checks at the start of §7c must pass.

---

### State D — published to both, SOME consumers have bumped their locks

Now consumers diverge and must be handled **per consumer, on the correct remote**. A
bumped consumer is in one of two sub-states:

- **`dir=config/ai` at/past `RENAME_BASE`** — it is *already failing* against the
  throwing stub. Rollback is the fix.
- **`dir=config/fleet`** — it migrated cleanly (its URL-move issue landed:
  vulcan=jwiegley/nixos-config#3, vps=#57, shared-work=#56). Rollback must walk both the
  URL and the lock back.

**Detect:** §4 shows both remotes HAVE the rename; at least one consumer shows either
`dir=config/fleet` or `dir=config/ai` at/past `RENAME_BASE`.

**Act:**
1. §7a + §6 first — `config/ai` must be restored and `REVERT_REV` on both remotes
   before any consumer URL revert means anything.
2. Then, **per consumer, on its own remote** (§7b):
   - **vulcan (gitea):** revert `nixos/flake.nix:54` to `?dir=config/ai`, preserving
     the current floating URL policy unless Q7 explicitly says to pin.
     `nix flake update nix-config nix-config-ai`. Push to gitea under
     `/etc/nixos/.nixos-build` locking. This reverts jwiegley/nixos-config#3.
   - **vps (github):** revert `vps/flake.nix:20` to `?dir=config/ai&ref=main`.
     `nix flake update nix-config nix-config-ai`. Push to github. Reverts #57.
   - **shared-work (github):** revert `andoria/flake.nix:31` to
     `?dir=config/ai&ref=main` **in the authoritative `~/.config/home-manager`**, not
     the `~/src/andoria` proxy. `nix flake update nix-config nix-config-ai`. Push to github.
     Reverts #56. Additionally confirm the `config/overlays.nix` stable-authority route
     still resolves (it imports `${inputs.nix-config}/config/overlays.nix` with
     `aiOverlay = inputs.nix-config-ai.overlays.default`; that path is not renamed, so
     it should — verify, do not assume).
3. A consumer that had **not** bumped stays as in State C (its next coherent paired
   update lands on `config/ai`; preserve the recorded URL policy).

**Verify:** §7c per consumer. For a consumer that was in stub-failure, additionally
confirm its own `nix flake check` / eval now succeeds (it was erroring before).

---

### State E — a consumer has ACTIVATED against the renamed revision

A consumer not only bumped but **switched** its host to a generation built from the
migrated lock. Reverting the URL and lock (State D) fixes future builds but does **not**
change the running system — that needs a generation rollback.

**Detect:** State D is true for a consumer *and* its host's current generation was built
after the URL move. List generations on the host (read-only):

```bash
# vulcan / vps (NixOS):
nixos-rebuild list-generations                     # or:
sudo nix-env -p /nix/var/nix/profiles/system --list-generations
# shared-work (Home Manager):
home-manager generations
```

The generation whose timestamp post-dates the consumer's URL-move commit is the one
built against the rename.

**Act — generation rollback is host-territory and separately authorized:**

- **vps / vulcan (NixOS):** the cleanest recovery is to rebuild from the *reverted*
  consumer lock (State D) and switch again — a **forward** activation onto the restored
  `config/ai`, which is explicitly authorization-gated and not granted by this runbook.
  As an immediate stopgap, the previous generation is still bootable:
  `sudo nixos-rebuild switch --rollback` (or select the prior generation from the
  bootloader / `nix-env -p /nix/var/nix/profiles/system --switch-generation N`). vulcan
  in particular pins its previous closure as a gcroot before switching
  (`doc/FLEET-DESIGN-PLAN.md` §7.8, `rollback-prev`), so the fallback closure survives GC.
- **shared-work (four NFS machines, ONE profile symlink):** rollback is **group-level**,
  not per-host — one profile-link move affects all four machines at once. Follow the
  §7.8 pattern before any activation: (1) build the reverted closure, (2) `nix copy` it
  to all four stores and prove residency with `nix path-info -r` on each, (3) confirm
  the *previous* closure is gcroot-pinned on all four, (4) only then activate the group
  symlink. Do **not** activate one machine and leave three on the renamed generation —
  the shared symlink makes that impossible anyway, which is exactly why the closure must
  be resident everywhere first.

**Verify:** on each host, the running generation resolves `config/ai` (its
`nix-config-ai` closure is the reverted subflake, not the stub); `home-manager
generations` / `nixos-rebuild list-generations` shows the rollback generation live; and
§7c still holds for the consumer's lock.

---

## 9. Closeout

- `bin/publish` (bare) reports **both** remotes at `REVERT_REV`.
- §7c passes for all three consumers: each locks `dir=config/ai`, via an immutable
  (`github`/`git`) fetcher, byte-stable, with both paired nodes at `REVERT_REV`.
  Vulcan's URL remains floating unless Q7 has separately authorized a pin.
- `config/ai` is a real subflake again (`nix flake check ./config/ai --all-systems
  --no-build` green; no `throw`); `config/fleet` and the stub are gone.
- `bin/cross-consumer-eval` green against the reverted working tree.
- The straggler tracker / stub-retirement gate (#63) is moot for the rolled-back path —
  there is no stub to retire once `config/ai` is real again.
- Record `RENAME_BASE`, `RENAME_TIP`, and `REVERT_REV`, the remote-parity confirmation, and each
  consumer's post-rollback lock rev in the #26 / #47 issue thread. The rename can be
  re-attempted later only by re-running #47 from the top.

---

## 10. Authorization ledger

| Action | Gate | Granted by |
|---|---|---|
| Authoring this runbook | none | — |
| `git revert` + dual re-publish of nix-config | **AG-DUALPUSH** (canonical on #18) | explicit, per invocation |
| Push each consumer URL revert to its remote | **AG-PUSH-CONSUMER** (per consumer) | explicit, per consumer (vulcan=gitea, vps=github, shared-work=github) |
| Any `switch`/activation in State E | separate activation authorization | explicit, per host/group; **never implied by this runbook** |

Signed commits only; stage explicit paths; do not bypass hooks; build and verify before
any activation.

---

## References

- Issues: [#26](https://github.com/jwiegley/nix-config/issues/26) (this runbook),
  [#47](https://github.com/jwiegley/nix-config/issues/47) (the rename it protects),
  [#63](https://github.com/jwiegley/nix-config/issues/63) (post-rename stragglers),
  #18 (AG-DUALPUSH / `bin/publish`); consumer URL-move issues
  jwiegley/nixos-config#3 (vulcan), #57 (vps), #56 (shared-work).
- Inventory: `test/inventory/consumer-inventory.json` (classification `stub-covered`).
- Tools: `bin/publish`, `bin/cross-consumer-eval`,
  `bin/update-overlay-test.py::test_root_inputs_do_not_reference_external_filesystems`.
- Design: `doc/FLEET-DESIGN-PLAN.md` §6.2 (immutable-fetcher / false-pass), §7.8
  (group-level activation + `rollback-prev` gcroot pin), Q5a (rename decision);
  `doc/UNIFIED-CONFIG-RESEARCH.md` (2026-07-27).
- Source lines: `config/ai/flake.nix:79-80` (whole-tree up-import);
  `nixos/flake.nix:54,58,164,312`; `vps/flake.nix:12,20,76`; `andoria/flake.nix:31,45,78`.
