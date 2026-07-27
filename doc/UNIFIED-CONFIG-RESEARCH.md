# Unified Fleet Configuration — External Research Findings

**Gathered:** 2026-07-27, via two `web-searcher` agents.
**Tooling caveat:** the Perplexity search API returned 401 for the entire session,
so both agents worked by direct `WebFetch` against primary sources rather than
broad discovery search. Reddit and `ajimenez.dev` were unreachable (blocked / 403)
and their claims were corroborated elsewhere. Confidence labels below are the
researchers' own, preserved rather than flattened.

---

## 1. Repository topology: consensus is one flake per repo

**Consensus.** The prevailing recommendation is a single flake per repository,
split internally by directory and modules — *not* nested flakes referencing one
another.

- NixOS Discourse, "Including flakes in the same repo" (Oct 2023): nesting flakes
  is "not very well-supported, and in general the right number of flakes per repo
  is 1", with an explicit warning against parent/child flake references.
  <https://discourse.nixos.org/t/including-flakes-in-the-same-repo/34119>
- Nix has no native support for multiple flake files per repo — open feature
  request Nix issue #12320. Multi-flake-in-one-repo fights the tool.

Reported failure modes when a flake consumes a *local* flake as an input:

1. **Relative-path narHash drift.** Sub-flakes referencing a parent via
   `path:../` produce a narHash that differs between machines at the same commit,
   yielding `cannot fetch input 'path:../?...narHash=...' because it uses a
   relative path`. (Discourse 34119.) This is the lock-drift mode directly.
2. **`follows` explosion.** Importing flakes pulls duplicate transitive `nixpkgs`
   copies (`nixpkgs`, `nixpkgs_2`, …) unless `inputs.X.follows` is threaded
   through every input. Nix issue #6549; Discourse #71174; Zakaria, "Automatic Nix
   flake follows" (2024-07-31) <https://fzakaria.com/2024/07/31/automatic-nix-flake-follows>.
   Sharp edge: Nix issue #14339 — removing `follows` doesn't respect the
   dependency's own lock.

---

## 2. The decisive correction: "closure" conflates three separate things

This is the most important research result, because the current architecture rests
on a conflation. There are three distinct costs, and the subflake split addresses
only one of them.

### (a) Evaluating hosts you don't need — NOT a problem; no subflake required

Flake outputs are a lazy attribute set. `darwin-rebuild switch --flake .#hera`
evaluates only that attribute path; `nix build` deliberately does not recurse into
sibling attributes (Nix issue #13470; corroborated by Discourse #32156 and the
nix-book outputs chapter).

**But** `nix flake check` and `nix flake show` *do* force all outputs — that is
their purpose. Nix issue #11818 (Nov 2024) is a feature request to blocklist
outputs precisely because `flake check` evaluates impure, host-specific
configurations and breaks CI. `nix flake check` evaluates only the *current*
system unless `--all-systems` is passed.

> Design consequence: a monorepo does not make any host build more, but it does
> make `nix flake check --all-systems` cost more. That cost is real and must be
> managed deliberately, not discovered later.

### (b) Source-tree ingestion — historically real, now obsolete *on this fleet*

Old behavior: Nix copied/checksummed the whole top-level git tree for any
operation, even `nix flake show`; a ~2 GB monorepo saw 90 s evaluations, and
scoping with `path://$PWD` cut 90 s → 8 s (Discourse #21282, 2022).

Modern fix: **lazy trees**, merged in Determinate Nix 3.5.1 (feature preview),
default-on from ~3.5.2, roughly 3× faster (12 s → 3.5 s).
<https://docs.determinate.systems/determinate-nix/lazy-trees/>, Discourse #64350.

> This fleet runs **Determinate Nix 3.11.2**, so lazy trees are already active.
> Splitting a subflake for ingestion speed is obsolete here.

### (c) Lock/input propagation to external consumers — the one legitimate reason

A subflake in a subdirectory has its **own** `flake.lock`; its inputs are never
visible to the parent's lock, and downstream consumers of the parent do not
inherit them. figsoda, "Developing Nix Libraries with Subflakes" (2023)
<https://figsoda.github.io/posts/2023/developing-nix-libraries-with-subflakes/>.
Documented trade-offs: two lockfiles; `../.` path access requires a git repo;
consuming parent-as-input causes lock churn (mitigable with `call-flake`).

> **This is exactly the `config/ai` case.** The existing subflake, and the paired
> root + `?dir=config/ai` consumer inputs, are the *justified* pattern — not the
> misconception. What is **not** justified by any of (a), (b), or (c) is the
> `flake.nix` / `flake-ai.nix` split and the `flake = false` consumption of the
> root repository.

### flake-parts isolation mechanisms, for reference

`perSystem` + `systems` (unlisted systems are never evaluated); outputs typed as
lazy attribute sets; `perInput` / `inputs'.<name>` to read a dependency's
per-system attributes without evaluating all of its systems. <https://flake.parts/>

`specialArgs` / `extraSpecialArgs` inject values needed during import resolution
and can therefore *gate imports*; `_module.args` injects values only after module
evaluation begins and so cannot select imports. This distinction matters for any
design that wants host metadata to choose which modules load.

---

## 3. Framework landscape, 2026

| Framework | State | Verdict |
|---|---|---|
| **flake-parts** | De facto standard, actively maintained, own NixOS Wiki page | Recommended *if* flake pieces will be factored into reusable modules; "otherwise likely unnecessary" |
| **snowfall-lib** | **Parked / stagnating** | Not recommended for new configurations in 2026 |
| **flakelight** | Niche but alive (~407 stars, no formal releases) | Good for simple/package flakes, not large heterogeneous fleets |
| **Hand-rolled** (`genAttrs` + `forAllSystems`) | Still respectable and common; Misterio77/nix-config uses it with no framework | Valid choice |

The honest middle position: adopt flake-parts only when module reuse actually pays
off — mccurdyc, 2026-02-01,
<https://www.mccurdyc.dev/posts/2026/02/nix-flake-parts-flake-utils-or-neither/>.

**Emerging trend, flagged with caution.** The "dendritic pattern" (Shahar Or /
`@mightyiam`) builds on flake-parts + `import-tree`: every non-entry file is an
auto-imported flake-parts module, and `deferredModule` lets one feature file
contribute NixOS + darwin + home-manager fragments at once, eliminating
`specialArgs` pass-through. <https://github.com/mightyiam/dendritic>. Adopters
include vic, Pol Dellaiera, and Gaétan Lepage; MatthiasBenaets/nix-config is a
concrete NixOS + darwin + standalone-HM example.

> **Tension worth naming:** the community anti-patterns document calls "magic
> auto-discovery" (importing via `builtins.readDir` scanning) an anti-pattern
> because it hides load order and dependencies — and dendritic's `import-tree` is
> exactly that mechanism. Given that this fleet's single worst defect is an
> *implicit overlay ordering contract*, adopting a pattern that further hides load
> order would be moving in the wrong direction.

**Genuine disagreement exists** between a "frameworks are unnecessary indirection"
camp (hand-rolled `genAttrs`) and the flake-parts/dendritic camp. This is not
settled.

---

## 4. Sharing a home-manager core across three activation contexts

Three converged strategies:

1. **Shared module tree + explicit builders.** The cleanest documented example is
   The One Nix: `lib/mkHost.nix` (NixOS), `mkDarwin.nix`, `mkHome.nix`
   (standalone) all import the same `home/shared/` tree, with a `standaloneUsers`
   list driving the output factory.
   <https://frankper.gitlab.io/the-one-nix/project-info/repo-structure/>

   **Key correctness insight:** it *gates context-sensitive modules*. Keyboard and
   locale are gated to `hmContext == "standalone" && isLinux` and made **inert**
   under NixOS/darwin, because the system layer owns those concerns there. This
   avoids double-application.

2. **Broadcast-and-gate.** wimpysworld/nix-config imports every module into every
   host in its layer; each module self-gates on host metadata
   (`lib.mkIf config.<ns>.host.is.workstation`). Host facts live in
   `registry-systems.toml` promoted to typed options.
   <https://github.com/wimpysworld/nix-config>

3. **Dendritic module pool.** One `config.flake.modules.homeManager` pool imported
   by all three contexts; OS specifics isolated at host level.

**Merging mechanism.** Use `imports` (which merges and de-duplicates). Do **not**
use the `import` builtin for composition, and do not use attrset-merge operators.
`lib.mkMerge` is the fallback but is "not recommended" — Discourse #77580 (May
2026), users waffle8946 / NobbZ.
<https://discourse.nixos.org/t/a-shared-home-manager-configuration-between-nixos-and-nix-darwin/77580>

**What breaks across contexts:**

- `home.homeDirectory`: `/Users/$USER` vs `/home/$USER`. Under NixOS/darwin modules
  HM can infer it; standalone usually must set it.
- **systemd vs launchd**: HM `services.*` are mostly systemd-user units and thus
  Linux-only. On darwin HM emits launchd agents, and many `services.*` modules have
  no darwin support. Gate with `lib.mkIf pkgs.stdenv.isLinux` or use per-platform
  module directories.
- `programs.*` availability varies by platform; keep behind guards.
- **`targets.genericLinux.enable`** — concrete effects, read from HM
  `modules/targets/generic-linux.nix`: appends distro paths to
  `xdg.systemDirs.data` (`/usr/share`, `/usr/local/share`, `/usr/share/ubuntu`,
  `/var/lib/snapd/desktop`) so `.desktop` files and icons resolve; sets
  `XCURSOR_PATH`; sources `nix.sh` and `hm-session-vars.sh` in bash init and resets
  `TERM`; extends zsh `fpath` with Debian/vendor completions; sets
  `NIX_PATH`/`TERMINFO_DIRS` for the systemd user session. Non-NixOS also typically
  needs `glibcLocales` + `LOCALE_ARCHIVE` and `nix-ld` for FHS binaries.
  **Enable ONLY on the standalone-foreign-distro path**; it should be a no-op and
  is not appropriate under NixOS or darwin.
- **Entry point differs**, and double-management is a known footgun — the
  gpg-agent launchd double-registration this fleet already hit is exactly this
  class of bug.

---

## 5. Modeling host variance — and the anti-patterns to avoid

**Override priority ladder** (Discourse #9028): `mkOptionDefault` 1500 →
`mkDefault` 1000 → plain 100 → `mkForce` 50 → `mkVMOverride` 10; lower wins.

**Design rule.** Put overridable values behind `mkDefault` in base modules and
expose real options for anything that varies per host, so per-host files *set*
values at normal priority rather than *fighting* base values with `mkForce`.
`mkForce` sprinkled per host is the smell that an option is missing.

**Explicitly named anti-patterns** (community NixOS anti-patterns document,
`nixos.freundcloud.com/NIXOS-ANTI-PATTERNS`), all directly relevant:

- **Unnecessary template functions.** One *parameterized* `mkSystem { hostname;
  profile; }` is good; a zoo of `mkWorkstation` / `mkServer` / `mkDevelopment`
  wrappers that each save one line is an anti-pattern. Call the base with
  parameters instead.
- **Magic auto-discovery.** Importing modules by scanning `builtins.readDir` hides
  load order and dependencies; prefer explicit `imports = [ ./core ./desktop ];`.
- **Trivial function wrappers.** Re-exporting `lib.mkIf` and friends adds nothing.
  *But* typed option helpers with defaults and descriptions (hlissner's
  `mkBoolOpt`) are generally accepted as adding real value.
- **Reading secrets during evaluation.** `builtins.readFile secret` lands
  cleartext in the store.

**Is a custom `options.mine.*` namespace worth it?** Genuine tension, not settled:

- *Pro* (hlissner, Misterio77): scales to many near-identical hosts; per-host
  files reduce to short lists of `mine.foo.enable = true`; avoids `mkForce`.
- *Con* (rochecompaan, thiscute): "The point of this refactor is not to make the
  config clever. The point is to make future changes obvious." Every custom
  `mkOption` without `description`/`example`/`type` is an opaque private API.
- *Practical synthesis:* introduce an option only when a setting varies across
  ≥ 2 hosts **and** toggling it pulls in a bundle of related configuration; keep it
  a thin layer over `lib`; document each option; do not build role-constructor
  functions on top. For per-host identity scalars (username, email, GPG key id),
  the dominant idiom is `specialArgs`/`extraSpecialArgs` or a small
  `mine.identity` submodule — **not** `mkForce`.

---

## 6. The NFS-shared-home hazard — highest-severity finding

From home-manager's standalone-mode internals
(<https://deepwiki.com/nix-community/home-manager/3.3-standalone-mode>):

- The profile resolves to `~/.nix-profile` (legacy) or
  `~/.local/state/nix/profiles/profile` (Nix ≥ 2.14 with
  `use-xdg-base-directories`).
- The GC root is a **single** symlink at
  `~/.local/state/home-manager/gcroots/current-home`, and generation links
  (`home-manager-N-link`) are numbered sequentially in the profile directory.
- Quoted: *"activating from machine B overwrites machine A's root… two machines
  writing to the same HM_PROFILE_DIR would create conflicting or overwritten
  generation entries… the entire state model assumes one active writer per home
  directory."*
- Recommended mitigation: **per-machine `$XDG_STATE_HOME`** or separate profile
  directories.
- Useful: `setFlakeAttribute()` already auto-tries hostname variants
  (`username@hostname`), so per-host *config selection* works out of the box. It
  is the on-disk *state* that collides.

Corroborated by Discourse "Nix with network-mounted home directories" (#35880),
where `~/.nix-profile` and channel/state metadata are flagged as "machine-specific
but shared". That thread produced **no clean recipe**, confirming this is
under-documented territory.

**Host-local idioms:**

- `XDG_RUNTIME_DIR` = `/run/user/UID`, a per-login tmpfs from `pam_systemd`,
  **guaranteed host-local, never NFS**. Canonical home for sockets, locks, PIDs.
- Redirect state and cache off NFS via `xdg.stateHome` / `xdg.cacheHome` to a
  host-local path (`/var/tmp/$USER`, `/local/$USER`, or hostname-suffixed). State
  **must** be host-local for correctness; cache for performance and locking.
- SQLite-backed state and any lockfile: NFS byte-range locking is unreliable —
  force these to host-local paths.
- **gpg-agent sockets are already safe:** the agent picks a socket dir from
  `/run/gnupg`, `/run`, `/var/run/gnupg`, `/var/run` with UID inserted, giving
  `/run/user/UID/gnupg` — host-local, not `~/.gnupg`. So an NFS-shared `~/.gnupg`
  still gets host-local sockets on systemd Ubuntu. Only when `/run/user/UID` is
  absent does it fall back to a hash-named dir in the home directory, which is the
  classic NFS breakage. (trustica.cz 2024-12-19; `wiki.gnupg.org/NFS`)

> A targeted follow-up is in flight to establish whether `xdg.stateHome` set as an
> *option* actually relocates home-manager's own gcroot and profile, or whether the
> activation script reads the *environment's* `$XDG_STATE_HOME` instead — which
> would mean per-host isolation cannot be purely declarative. Design decisions
> depending on this are deferred until answered.

---

## 7. Secrets across mixed activation contexts

**Corrected misconception.** Both sops-nix and agenix HM modules require a systemd
**user service** on Linux; **neither** has a plain `home.activation` fallback.
Verified from source:

- sops-nix `modules/home-manager/sops.nix`: systemd user service `sops-nix` gated
  on `pkgs.stdenv.hostPlatform.isLinux`; launchd agent
  `org.nix-community.home.sops-nix` defined unconditionally. Darwin is
  first-class (logs to `~/Library/Logs/SopsNix/`).
- agenix `modules/age-home.nix`: Linux = systemd user service `agenix`
  (`Type=oneshot`, `WantedBy=default.target`); macOS = launchd agent
  `activate-agenix` (`RunAtLoad=true`). Explicitly **no** `home.activation` path —
  "non-systemd Linux systems get nothing."

Consequences for the four Ubuntu standalone-HM machines:

- Both work **if** a systemd user session exists. Headless/always-on use needs
  `loginctl enable-linger $USER`, or secrets are absent until first login.
- Both resolve secret paths from `$XDG_RUNTIME_DIR` at **runtime**. If
  `home-manager switch` runs where `$XDG_RUNTIME_DIR` is unset (some `su`, cron,
  or CI shells), path expansion breaks.
- Dependent user services must order after the secrets unit.
- Eval-time secret use is impossible in both — decryption is activation-time only.

**NFS path hazard, and the one concrete difference between the tools:**

- **sops-nix** stages decrypted secrets in `$XDG_RUNTIME_DIR/secrets.d`
  (host-local, good) but the *symlink* `path` defaults under `xdg.configHome` →
  `~/.config/sops-nix/secrets/<name>`. On a shared `$HOME`, four machines write
  symlinks into the same NFS directory, each targeting its own
  `$XDG_RUNTIME_DIR`, so from any other host the link dangles. **Fix:** set `path`
  with the `%r` placeholder (`%r` = `$XDG_RUNTIME_DIR` on Linux,
  `getconf DARWIN_USER_TEMP_DIR` on darwin), e.g. `path = "%r/secrets/foo"`.
- **agenix** defaults `secretsDir` *and* `path` to `$XDG_RUNTIME_DIR/agenix/<name>`
  — host-local out of the box. This is agenix's one concrete edge for a
  shared-home fleet, and sops-nix matches it once `%r` is set.

**Keeping key material out of the store:**

- agenix `age.identityPaths` entries must be **strings**
  (`"/home/johnw/.ssh/id_ed25519"`), never Nix path literals — a path literal
  copies the private key into the world-readable store.
- sops-nix supports age (including `ssh-to-age` from an existing
  `~/.ssh/id_ed25519`, so no extra keyfile), PGP, and YubiKey via GnuPG. On NixOS
  it can auto-import the SSH host key. agenix uses SSH keys directly but has **no
  ssh-agent support**, so password-protected SSH keys "do not work well".
- **Per-host signing identity is not a secrets problem.** The public signing key
  id, email, and `user.signingkey` are not secrets — parameterize them per host
  via options or `specialArgs`. The private key stays in `~/.gnupg` / `~/.ssh` or
  is delivered to `/run`, never the store. On the NFS fleet an identical
  `~/.gnupg` across the four machines is fine (same keys); only git config
  (`user.email`, `user.signingkey`, `commit.gpgsign`) diverges, and that is plain
  per-host configuration.

**Environment-only tokens** (Stapelberg, 2025-08-24,
<https://michael.stapelberg.ch/posts/2025-08-24-secret-management-with-sops-nix/>):

1. **`EnvironmentFile`** — store a whole `KEY=value` block as one secret and
   reference `EnvironmentFile = [ config.sops.secrets."svc/env".path ]`. Keeps
   values out of the store *and* out of `argv`.
2. **Dedicated `*File` / `keyFile` options** — prefer wherever a module offers one.
3. **systemd `LoadCredential`** — the service reads
   `/run/credentials/<unit>/<name>`, avoiding environment variables entirely.
   systemd's own documentation says environment variables are "not suitable for
   passing secrets" (Discourse #71102). Best option on NixOS hosts.

**sops-nix `templates`** render a config file interpolating a secret into a
non-secret template at a runtime path, never the store. Per the NixOS wiki this is
the only *major* tool with templating (agenix has none).

**Community split is real, with no consensus winner.** NixOS Wiki "Comparison of
secret managing schemes" (edited 2026-05-20) is neutral and calls both "the most
popular". Pro-sops-nix: Stapelberg. Pro-agenix: fzakaria (2024-07-12, "focus
solely on agenix"), Andreas Gohr — appeal is fewer moving parts and no GnuPG
(sops-nix's own README warns GnuPG "might break in hilarious ways").

**Researcher's read for this fleet:** sops-nix edges it — one tool covering NixOS
(systemd, `LoadCredential`, `EnvironmentFile`), darwin (launchd, first-class), and
Ubuntu standalone HM, plus templating — provided the HM `path` is redirected to
`%r` on the NFS machines. **This also happens to be what Vulcan already uses**, so
it is the continuity choice as well.

**Stated caveats:** agenix's README notes it is unaudited and that age is not
post-quantum safe (harvest-now-decrypt-later); the latter applies to sops-nix too,
since sops + age shares the primitive. The NixOS Wiki comparison does **not**
cover the HM / darwin / standalone dimensions — those findings came from reading
module source directly.
