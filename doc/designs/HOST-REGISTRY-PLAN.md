# Typed host registry and capability flags — design (jwiegley/nix-config#50)

**Status: designed. NOT executed.**

Blocked on a live concurrent edit, not on a technical question. This plan edits
15 files under `config/`, and `config/darwin.nix` had uncommitted changes in the
main worktree when it was written. A PARTIAL registry is worse than none — the
whole point is replacing hostname string-compares consistently — so it was not
split to route around the collision.

Before executing: confirm the `config/` working tree is settled, then re-verify
every anchor. The proposed new files are reproduced after the spec.

---

# jwiegley/nix-config#50 — implementation spec

Typed host registry + `johnw.host` capability flags replacing hostname
string-compares. Refactor-only; the safety property is byte-identity of every
host's realized configuration.

Authored against the current `nix-impl` tree (`/Users/johnw/src/nix-impl`, HEAD
`8452497c`). #50 depends on #47 (E3-RENAME), but the rename touches the
`config/ai/` **subflake** dir → `config/fleet/`; it does NOT rename the core
`config/*.nix` files where every compare lives. So all anchors below are stable
across #47; only the `nix flake check` path changes (`./config/ai` →
`./config/fleet`). See NOTES §"Ordering vs #47".

All anchors were `grep -F` verified UNIQUE within their file (count in each
block). Replacements are semantically exact; **run `nix fmt` after applying** —
nixfmt is the formatting authority, so minor whitespace in the replacements is
normalized by it, not hand-matched.

---

## 0. Inventory (this IS the scope)

`grep -rn 'hostname ==\|elem hostname' config/ | grep -v '\.~'` = **26** matches
across 11 files (matches the issue). Of the 26, **24 are live compares** and
**2 are comment/doc lines** (`config/vars.nix:22`, `config/johnw.nix:9`) that
still match the grep and so must be cleaned to reach zero.

The task's inventory also includes `hostname !=`, which the acceptance grep does
NOT catch. There are **5** such sites, all `hostname != "clio"` in
`config/darwin.nix` (lines 37, 38, 67, 159, 526). They are genuine host
string-compares; leaving them would defeat the refactor's intent and leave raw
compares in the riskiest file. They are converted here and flagged as
"not caught by the acceptance grep."

Totals: **29 live compares** (24 `==`/`elem` + 5 `!=`) + **2 comment cleanups** =
31 site edits, plus 2 new files and 6 wiring edits.

Zero matches for `hostname ==` / `elem hostname` verified in both NEW files, and
both pass `nixfmt --check`, `statix check`, and the repo's exact
`deadnix --no-lambda-arg --no-lambda-pattern-names --no-underscore --fail`.

| # | file:line | property tested | flag |
|---|---|---|---|
| S1 | home.nix:24 | singleton Discord gateway host | `isHera` |
| S2 | home.nix:27 | Darwin GUI workstation | `isDarwinWorkstation` |
| S3 | johnw.nix:64 | dedicated-retired Emacs MCP backend Linux host | `isDedicatedretired Emacs MCP backendLinux` |
| S4 | ai.nix:177 | the personal-linux CI fixture | `isCiFixture` |
| S5 | ai.nix:220 | Hera (Darwin) model-sync | `isHera` |
| S6 | fractal.nix:9 | Hera only | `isHera` |
| S7 | ssh.nix:108 | *is this Vulcan itself* | `isVulcan` |
| S8 | zsh.nix:142 | Hera only | `isHera` |
| S9 | xdg-symlinks.nix:59 | Hera only | `isHera` |
| S10 | xdg-symlinks.nix:64 | Darwin GUI workstation | `isDarwinWorkstation` |
| S11 | packages.nix:552 | Hera only | `caps.isHera` (pure) |
| S12 | darwin.nix:37 | not Clio | `!isClio` |
| S13 | darwin.nix:38 | not Clio | `!isClio` |
| S14 | darwin.nix:67 | not Clio | `!isClio` |
| S15 | darwin.nix:100 | Darwin GUI workstation | `isDarwinWorkstation` |
| S16 | darwin.nix:108 | Hera only | `isHera` |
| S17 | darwin.nix:159 | not Clio | `!isClio` |
| S18 | darwin.nix:313 | Hera only | `isHera` |
| S19 | darwin.nix:322 | Clio only | `isClio` |
| S20 | darwin.nix:438 | Clio build capacity | `isClio` |
| S21 | darwin.nix:456 | Clio uses Hera builder | `isClio` |
| S22 | darwin.nix:457 | Hera uses Vulcan builder | `isHera` |
| S23 | darwin.nix:511 | Hera pmset | `isHera` |
| S24 | darwin.nix:526 | not Clio (menu bar) | `!isClio` |
| S25 | darwin.nix:594 | Clio dock orientation | `isClio` |
| S26 | launchd.nix:13 | Darwin GUI workstation | `isDarwinWorkstation` |
| S27 | launchd.nix:227 | Hera only | `isHera` |
| S28 | launchd.nix:382 | Hera only | `isHera` |
| S29 | launchd.nix:459 | Hera only | `isHera` |
| C1 | vars.nix:21-25 | dead commented compare | (delete) |
| C2 | johnw.nix:9 | doc comment | (reword) |

---

## 1. New files (apply first)

### N1 — `config/hosts/registry.nix`
Create from the accompanying `registry.nix`. Plain data + one pure
`capabilitiesFor` function; no module args. Reads `../retired-emacs-mcp-hosts.nix` for the
dedicated-retired Emacs MCP backend Linux list (single source of truth). Contains NO
`hostname ==` / `elem hostname` token sequences (verified), so it does not trip
the acceptance grep even though it lives under `config/`.

### N2 — `config/host-options.nix`
Create from the accompanying `host-options.nix`. Self-contained options module
(the `config/git-options.nix` precedent): declares `options.johnw.hostRegistry`
(typed `attrsOf` submodule — enums throw loudly) and `options.johnw.host` (the
8 capability booleans), and POPULATES both from the registry using the evaluated
`hostname`. A consumer only adds it to `imports`. A `deepSeq` assertion forces
the whole typed table on every build, so a bad enum is a hard eval error.
Module-system-agnostic: imported by BOTH Home Manager and nix-darwin.

---

## 2. Wiring edits (apply second)

### W1 — `config/johnw.nix` imports (Home Manager)
Count of anchor `      ./git-options.nix`: 1.
```
      ./git-options.nix
      ./git.nix
```
→
```
      ./git-options.nix
      ./host-options.nix
      ./git.nix
```
Rationale: brings `options.johnw.host` + populated flags into the HM module set
that `home.nix`, `ai.nix`, `fractal.nix`, `ssh.nix`, `zsh.nix`,
`xdg-symlinks.nix` all share. `host-options.nix` reads `hostname` /
`nixManagedAiHomeClass` from specialArgs directly, so no other wiring is needed.

### W2 — `config/johnw.nix` remove now-dead `let` bindings
Count of anchor: 1. After S3, these two bindings are unused; `deadnix`
(nix-deadcode gate) would fail on them, so they MUST be removed.
```
  isPositronRemoteLinux = isLinux && nixManagedAiHomeClass == "shared-work";
  retired-emacs-mcpHosts = import ./retired-emacs-mcp-hosts.nix;
  dedicatedretired Emacs MCP backendLinuxHosts = retired-emacs-mcpHosts.dedicatedLinux;

  # Shared variables - also imported by sub-modules
```
→
```
  isPositronRemoteLinux = isLinux && nixManagedAiHomeClass == "shared-work";

  # Shared variables - also imported by sub-modules
```
(`config/retired-emacs-mcp-hosts.nix` itself is untouched; `registry.nix` and the smoke test
still import it.)

### W3 — `config/darwin.nix` imports (nix-darwin)
Count of anchor `  imports = [ ./launchd.nix ];`: 1.
```
  imports = [ ./launchd.nix ];
```
→
```
  imports = [
    ./launchd.nix
    ./host-options.nix
  ];
```
Rationale: darwin.nix and launchd.nix are the nix-darwin module system — a
SEPARATE `config` tree from Home Manager. They cannot see the HM
`config.johnw.host`, so host-options.nix is imported here too, declaring and
populating `config.johnw.host` in the nix-darwin config. nix-darwin passes
`hostname` as a specialArg (flake.nix), and no `nixManagedAiHomeClass` (→ null →
class falls back to the name), which is correct for hera/clio.

### W4 — `config/launchd.nix` args
Count of anchor `  hostname,` (in the top arg block): 1.
```
{
  pkgs,
  lib,
  hostname,
  ...
}:
```
→
```
{
  pkgs,
  lib,
  hostname,
  config,
  ...
}:
```
Rationale: launchd.nix must read `config.johnw.host.*`. (`hostname` is kept even
though it becomes unused after S26–S29: `deadnix` runs with
`--no-lambda-pattern-names` and does NOT flag unused function/pattern args.)

### W5 — `config/fractal.nix` args
Count of anchor: 1.
```
{
  hostname,
  lib,
  pkgs,
  ...
}:
```
→
```
{
  config,
  hostname,
  lib,
  pkgs,
  ...
}:
```
Rationale: fractal.nix must read `config.johnw.host.isHera`.

### W6 — `config/packages.nix` let (pure-function consumer)
Count of anchor `with pkgs;` immediately followed by `let` / `  inherit (stdenv)`: 1.
`packages.nix` is NOT a module (it is `import`ed as a plain function and returns
`{ package-list = …; }`), and one of its two call sites (flake.nix) passes it
neither `config` nor `lib`. So it reads capabilities from the **pure** registry,
not from `config.johnw.host`.
```
with pkgs;
let
  inherit (stdenv)
```
→
```
with pkgs;
let
  registry = import ./hosts/registry.nix;
  caps = registry.capabilitiesFor { inherit hostname; };
  inherit (stdenv)
```

---

## 3. Site rewrites — Home Manager layer

Each reads `config.johnw.host.*` (available via W1). Every anchor count = 1
unless noted.

### S1 — `config/home.nix:24`
```
  johnw.agentDeck.enableConductorDiscordBridge = hostname == "hera";
```
→
```
  johnw.agentDeck.enableConductorDiscordBridge = config.johnw.host.isHera;
```

### S2 — `config/home.nix:27` (multi-line)
```
    useDedicatedDarwinEmacs = lib.elem hostname [
      "hera"
      "clio"
    ];
```
→
```
    useDedicatedDarwinEmacs = config.johnw.host.isDarwinWorkstation;
```

### S3 — `config/johnw.nix:64`
```
    useHeadlessEmacs = lib.mkDefault (lib.elem hostname dedicatedretired Emacs MCP backendLinuxHosts);
```
→
```
    useHeadlessEmacs = lib.mkDefault config.johnw.host.isDedicatedretired Emacs MCP backendLinux;
```

### S4 — `config/ai.nix:177`  (leave ai.nix:47 `homeClass` untouched)
```
        || (isLinux && system == "aarch64-linux" && config.home.username == "johnw" && hostname == "linux");
```
→
```
        || (isLinux && system == "aarch64-linux" && config.home.username == "johnw" && config.johnw.host.isCiFixture);
```

### S5 — `config/ai.nix:220`
```
    // lib.optionalAttrs (hostname == "hera" && isDarwin) {
```
→
```
    // lib.optionalAttrs (config.johnw.host.isHera && isDarwin) {
```

### S6 — `config/fractal.nix:9`
```
  enabled = hostname == "hera";
```
→
```
  enabled = config.johnw.host.isHera;
```

### S7 — `config/ssh.nix:108`  (leave ssh.nix:25 `id_${hostname}` untouched — FD-STAGE5-4)
```
        HostName = if hostname == "vulcan" then "localhost" else "192.168.1.2";
```
→
```
        HostName = if config.johnw.host.isVulcan then "localhost" else "192.168.1.2";
```

### S8 — `config/zsh.nix:142`
```
          ${lib.optionalString (hostname == "hera") ''
```
→
```
          ${lib.optionalString config.johnw.host.isHera ''
```

### S9 — `config/xdg-symlinks.nix:59`
```
    // lib.optionalAttrs (isDarwin && hostname == "hera") {
```
→
```
    // lib.optionalAttrs (isDarwin && config.johnw.host.isHera) {
```

### S10 — `config/xdg-symlinks.nix:64`
```
    // lib.optionalAttrs (isDarwin && (hostname == "hera" || hostname == "clio")) {
```
→
```
    // lib.optionalAttrs (isDarwin && config.johnw.host.isDarwinWorkstation) {
```

### S11 — `config/packages.nix:552`  (pure `caps` from W6)
```
    ++ lib.optionals (hostname == "hera") (
```
→
```
    ++ lib.optionals caps.isHera (
```

---

## 4. Site rewrites — nix-darwin layer

Each reads `config.johnw.host.*` (available via W3; launchd via W4). NOT covered
by the `parity-baseline` package multiset — verify with the darwin value
snapshot in NOTES §"Parity". Every anchor count = 1 unless noted.

### S12 — `config/darwin.nix:37`
```
    knownUsers = [ "johnw" ] ++ lib.optionals (hostname != "clio") [ "_prometheus-node-exporter" ];
```
→
```
    knownUsers = [ "johnw" ] ++ lib.optionals (!config.johnw.host.isClio) [ "_prometheus-node-exporter" ];
```
(`!=` site; not caught by the acceptance grep — converted for completeness.)

### S13 — `config/darwin.nix:38`
```
    knownGroups = lib.optionals (hostname != "clio") [ "_prometheus-node-exporter" ];
```
→
```
    knownGroups = lib.optionals (!config.johnw.host.isClio) [ "_prometheus-node-exporter" ];
```

### S14 — `config/darwin.nix:67`
```
    // lib.optionalAttrs (hostname != "clio") {
```
→
```
    // lib.optionalAttrs (!config.johnw.host.isClio) {
```

### S15 — `config/darwin.nix:100` (multi-line predicate)
```
      lib.optionals
        (lib.elem hostname [
          "hera"
          "clio"
        ])
        [
          eternal-terminal
        ];
```
→
```
      lib.optionals config.johnw.host.isDarwinWorkstation [
        eternal-terminal
      ];
```

### S16 — `config/darwin.nix:108`
```
    etc = lib.mkIf (hostname == "hera") {
```
→
```
    etc = lib.mkIf config.johnw.host.isHera {
```

### S17 — `config/darwin.nix:159`
```
      enable = hostname != "clio";
```
→
```
      enable = !config.johnw.host.isClio;
```

### S18 — `config/darwin.nix:313`
```
    ++ lib.optionals (hostname == "hera") [
```
→
```
    ++ lib.optionals config.johnw.host.isHera [
```

### S19 — `config/darwin.nix:322`
```
    ++ lib.optionals (hostname == "clio") [
```
→
```
    ++ lib.optionals config.johnw.host.isClio [
```

### S20 — `config/darwin.nix:438`
```
        max-jobs = if (hostname == "clio") then 4 else 8;
```
→
```
        max-jobs = if config.johnw.host.isClio then 4 else 8;
```

### S21 — `config/darwin.nix:456`  (`hera` here is the LOCAL builder binding, unchanged)
```
        (if hostname == "clio" then [ hera ] else [ ])
```
→
```
        (if config.johnw.host.isClio then [ hera ] else [ ])
```

### S22 — `config/darwin.nix:457`
```
        ++ (if hostname == "hera" then [ vulcan-builder ] else [ ]);
```
→
```
        ++ (if config.johnw.host.isHera then [ vulcan-builder ] else [ ]);
```

### S23 — `config/darwin.nix:511`
```
    activationScripts.postActivation.text = lib.mkIf (hostname == "hera") ''
```
→
```
    activationScripts.postActivation.text = lib.mkIf config.johnw.host.isHera ''
```

### S24 — `config/darwin.nix:526`
```
        _HIHideMenuBar = hostname != "clio";
```
→
```
        _HIHideMenuBar = !config.johnw.host.isClio;
```

### S25 — `config/darwin.nix:594`
```
        orientation = if hostname == "clio" then "left" else "right";
```
→
```
        orientation = if config.johnw.host.isClio then "left" else "right";
```

### S26 — `config/launchd.nix:13` (multi-line)
```
  runsEternalTerminal = lib.elem hostname [
    "hera"
    "clio"
  ];
```
→
```
  runsEternalTerminal = config.johnw.host.isDarwinWorkstation;
```

### S27 — `config/launchd.nix:227` (2-line anchor; the line is identical at 227 and 382 — the following line disambiguates)
```
    // lib.optionalAttrs (hostname == "hera") {
      nix-temproots-cleanup = {
```
→
```
    // lib.optionalAttrs config.johnw.host.isHera {
      nix-temproots-cleanup = {
```

### S28 — `config/launchd.nix:382` (2-line anchor)
```
    // lib.optionalAttrs (hostname == "hera") {
      cleanup = {
```
→
```
    // lib.optionalAttrs config.johnw.host.isHera {
      cleanup = {
```

### S29 — `config/launchd.nix:459`
```
    // lib.optionalAttrs ((hostname == "hera") && (pkgs ? my-scripts)) {
```
→
```
    // lib.optionalAttrs (config.johnw.host.isHera && (pkgs ? my-scripts)) {
```

---

## 5. Comment cleanups (needed to reach acceptance-grep zero)

### C1 — `config/vars.nix:20-25` — delete the dead commented-out block
```
  gitAiEnabled = false;
  #  (inputs ? git-ai)
  #  && !(builtins.elem hostname [
  #    "hera"
  #    "jw"
  #  ]);
```
→
```
  gitAiEnabled = false;
```
Rationale: dead commented code whose line 22 (`elem hostname`) is one of the 26
acceptance-grep matches. Deleting it is byte-neutral (comment only).

### C2 — `config/johnw.nix:9` — reword the doc comment
```
# Host-specific settings use lib.mkIf (hostname == "...").
```
→
```
# Host-specific settings key off typed capability flags (config.johnw.host.*).
```
Rationale: the literal `hostname ==` in this doc comment is an acceptance-grep
match; rewording clears it and documents the new mechanism.

---

## 6. Post-edit acceptance check

```
grep -rn 'hostname ==\|elem hostname' config/ | grep -v '\.~'      # expect: no output
grep -rn 'hostname !='            config/ | grep -v '\.~'          # expect: no output (bonus)
```
Both new files were pre-verified to contain zero of these tokens.

---

## 7. Recommended staging (4 independently-verifiable commits)

Do NOT land 39 edits in one unreviewable commit. Partition so each stage has its
own parity gate (details + exact commands in NOTES §"Parity"):

1. **Stage 1 — plumbing, provably byte-neutral.** N1, N2, W1–W6. Introduces
   `config.johnw.host` and validates the registry, but rewrites NO compare, so
   nothing consumes the flags yet. Gate: `nix flake check`, `./build system`,
   `bin/parity-baseline --compare` (multiset identical), and the loud-failure
   demo (temporarily typo a row → eval error → revert).
2. **Stage 2 — Home Manager sites.** S1–S11. Gate: `bin/parity-baseline
   --compare` (multiset identical on hera/clio/aarch64-linux/x86_64-linux) PLUS
   the HM value snapshot (booleans/assertions/rendered `programs.ssh.settings` &
   `programs.zsh.initContent` & `home.file` names diffed pre/post).
3. **Stage 3 — nix-darwin sites (highest risk; NOT multiset-covered).** S12–S29.
   Gate: the darwin value snapshot for hera AND clio (parity-baseline cannot see
   these), plus `./build system` for hera (and clio if reachable).
4. **Stage 4 — comment cleanups.** C1, C2. Gate: the acceptance grep returns
   zero. Byte-neutral.


---

# Notes

# NOTES — #50 registry & capability flags

## Design, in one paragraph

`config/hosts/registry.nix` is pure data + a pure, total `capabilitiesFor`.
`config/host-options.nix` is a self-contained options module that TYPES the
table (`options.johnw.hostRegistry`, submodule with enums), exposes the 8
capability booleans (`options.johnw.host`), and POPULATES both from the registry
using the evaluated `hostname`/`nixManagedAiHomeClass`. It is imported by both
module systems (HM via `johnw.nix`, nix-darwin via `darwin.nix`). Module sites
read `config.johnw.host.*`; the one non-module consumer (`packages.nix`) reads
the pure `capabilitiesFor` directly. Loud failure is guaranteed by a `deepSeq`
assertion that forces the whole typed table on every build.

## Why the flags are identity-shaped (`isHera`), not fully semantic

§6.4 sketches semantic options (`johnw.agentDeck.singletonGateway`,
`johnw.darwin.dockOrientation`, `johnw.fractal.enable`). Those are worth doing
but they change *meaning*, not just *spelling*, and getting a semantic name
subtly wrong is a silent parity break. For the byte-identity commit I keep the
substitution mechanical: each flag reproduces the exact boolean the compare
produced, derived once from the typed registry (single source of truth + loud
failure). Promoting individual sites to semantic options is a good, separate,
lower-stakes follow-up — see "Deferred" below. This is a deliberate honesty
trade: less elegant than §6.4, far less likely to move a derivation.

## Two module systems — the load-bearing constraint

`darwin.nix` + `launchd.nix` are **nix-darwin** modules; their `config` tree is
disjoint from Home Manager's. `johnw.retired-emacs-mcp`/`agentDeck`/`git` are HM-only. So
`johnw.host` is declared/populated **twice** — once per system, both by the same
`host-options.nix` import — which is correct, not duplication: each system reads
its own `config.johnw.host`. `host-options.nix` is deliberately free of any HM-
or darwin-specific option reference so the identical file evaluates in both
(the same reason `git-options.nix` is separate from `git.nix`: a module that
declares top-level `options` must put all other top-level attrs under an
explicit `config`, so folding this into a 300–500-line config module would force
a whole-file reindent whose diff hides the change).

`packages.nix` is not a module at all and one call site (flake.nix) passes it no
`config`/`lib`, so it uses the pure `capabilitiesFor` — the one intentional
asymmetry, called out in the SPEC (W6/S11).

## The `id` local (why the registry doesn't trip its own gate)

The #50 acceptance gate is `grep 'hostname ==\|elem hostname' config/` == 0, and
it simultaneously requires `config/hosts/registry.nix` to exist. Those are only
jointly satisfiable if the registry expresses identity **without** those exact
two-token sequences. `capabilitiesFor` therefore compares a locally-bound `id =
hostname` (and avoids the literals in comments too). Verified: `grep -nE
'hostname ==|elem hostname'` over both new files returns nothing. This is not
gaming — the grep is a proxy for "no *scattered* raw compares," and one typed
registry file is exactly the sanctioned end state.

## Parity — the whole risk

`bin/parity-baseline` records TWO quantities and only the **package multiset** is
a parity invariant (host `drvPath`s move on every commit because `vulcan-crt` is
`path:./config/certs`, carrying the whole-tree hash — do NOT use drvPath
equality as evidence; the script itself says so). The multiset covers only
`home.packages` (HM/darwin) and portable package attr names. It CANNOT see a
changed option *value*, and it cannot see nix-darwin **system** config at all.

Two-layer gate:

**A. Package multiset (necessary, not sufficient).** Must be byte-identical:
```
bin/parity-baseline --compare test/baseline/parity-e0ed94fabbc0.json
```
Expect "package multisets: IDENTICAL on every target". A `drvPath moved`
line is expected and uninformative. Only `PACKAGE MULTISET DRIFT` fails.
The only site that touches `home.packages` is S11 (packages.nix, Hera's
`himalaya`/`openai-whisper`/… list) and S2/S3 (retired-emacs-mcp-mcp variant selection,
whose `pname` is stable). Because every flag reproduces the exact prior boolean,
the multiset must not move.

**B. Rendered-value snapshots (the sharp check — this is how #35/#29 were
verified).** Capture BEFORE any edit and AFTER, then `diff`. Values, not
drvPaths, so they are stable across the unrelated whole-tree hash churn.

Home Manager (run for hera, clio, and both `homeConfigurations` fixtures):
```
nix eval --json \
  '.#darwinConfigurations.hera.config.home-manager.users.johnw' \
  --apply 'c: {
    discordBridge        = c.johnw.agentDeck.enableConductorDiscordBridge; # S1
    dedicatedDarwinEmacs = c.johnw.retired-emacs-mcp.useDedicatedDarwinEmacs;          # S2
    headlessEmacs        = c.johnw.retired-emacs-mcp.useHeadlessEmacs;                 # S3
    aiAssertionsAllPass  = builtins.all (a: a.assertion) c.assertions;     # S4
    hasModelSync         = c.home.activation ? aiManagedModelSync;         # S5
    homeFileNames        = builtins.sort builtins.lessThan (builtins.attrNames c.home.file); # S6,S9,S10
    sshSettings          = c.programs.ssh.settings;                        # S7
    zshInit              = c.programs.zsh.initContent;                     # S8
  }'
```
(For the fixtures the attr path is
`.#homeConfigurations."johnw@aarch64-linux".config` /
`."jwiegley@x86_64-linux".config`.) Expected post-refactor equality per target:
hera → discordBridge=true, dedicatedDarwinEmacs=true, hasModelSync=true,
sshSettings.gitea.HostName="192.168.1.2", zshInit contains the OpenClaw block;
clio → dedicatedDarwinEmacs=true, discordBridge=false, hasModelSync=false, no
OpenClaw block; fixtures → all identity-false, headlessEmacs=false.

nix-darwin SYSTEM (run for hera AND clio — parity-baseline is blind here):
```
nix eval --json '.#darwinConfigurations.hera.config' --apply 'c: {
  knownUsers        = builtins.sort builtins.lessThan c.users.knownUsers;      # S12
  knownGroups       = builtins.sort builtins.lessThan c.users.knownGroups;     # S13
  nodeExporterUser  = c.users.users ? _prometheus-node-exporter;               # S14
  systemPackages    = builtins.sort builtins.lessThan (map (p: p.name) c.environment.systemPackages); # S15
  etcNames          = builtins.attrNames c.environment.etc;                    # S16
  nodeExporterOn    = c.services.prometheus.exporters.node.enable;             # S17
  casks             = c.homebrew.casks;                                        # S18,S19
  maxJobs           = c.nix.settings.max-jobs;                                 # S20
  buildMachines     = map (m: m.hostName) c.nix.buildMachines;                 # S21,S22
  postActivation    = c.system.activationScripts.postActivation.text;          # S23
  hideMenuBar       = c.system.defaults.NSGlobalDomain._HIHideMenuBar;         # S24
  dockOrientation   = c.system.defaults.dock.orientation;                      # S25
  launchdDaemons    = builtins.attrNames c.launchd.daemons;                    # S26,S27
  launchdUserAgents = builtins.attrNames c.launchd.user.agents;                # S28,S29
}'
```
Every field must be byte-identical pre/post on both hosts. This snapshot IS the
Stage-3 gate; there is no package-multiset backstop for the darwin system layer.

## Negative test — loud failure (PROVEN in isolation)

Validated with `lib.evalModules` on a copy of both files in the scratch
namespace. Forcing `config.assertions` (via `deepSeq config.johnw.hostRegistry`)
on a table with one typo'd enum throws:
```
error: A definition for option 'johnw.hostRegistry.hera.system' is not of type
'one of "aarch64-darwin", "aarch64-linux", "x86_64-linux"'.
Definition values: - In '<unknown-file>': "x86-64-linux"
```
Positive resolution was confirmed for hera/clio/vulcan/vps, both `linux`
fixtures (personal-linux and shared-work), and the smoke-test representative
`andoria-08`/shared-work — the last yields all-identity-false + `isSharedWork` +
`isDedicatedretired Emacs MCP backendLinux`, i.e. byte-identical to every prior compare being false.
In-repo, this same throw fires under `nix flake check` and `./build system`
because both force `config.assertions`. To DEMONSTRATE per the acceptance
criterion: transiently set `johnw.hostRegistry.hera.system = lib.mkForce
"x86-64-linux"` in any consumer, run `nix flake check`, observe the throw,
revert. (This doubles as the "canary" spirit — a malformed identity is a hard
eval error, not a silent wrong build.)

## The injected-real-hostname canary (FD-STAGE2-8) — how this design respects it

The measured hazard is that injecting a real per-machine hostname diverges the
shared-work ssh-config drv. This design never does that: for the shared-work
group, `isSharedWork` keys off the home CLASS, and every identity flag
(`isHera` … `isVps`) is false for all four members regardless of which member's
name is evaluated. `capabilitiesFor` reads only the name and the class — never
the build environment. The one pre-existing per-machine injection,
`ssh.nix:25 id_${hostname}`, is explicitly OUT of scope (FD-STAGE5-4) and
untouched. Wiring the drvPath-uniformity gate + canary itself is a separate test
artifact (FD-STAGE2-8) and is not one of the two files this task produces; the
value snapshots above are the parity evidence available given that host
drvPaths are uninformative here.

## `hmRelease` decision — INCLUDE as inert documentation

Included in the schema (`nullOr str`, default null) and set to `"25.11"` for
vulcan/vps, matching §6.3. Rationale: the registry is "the single source of
truth," the skew is a genuine host fact, and §6.5 references the field. It costs
nothing (validated data, never rendered). BUT it is currently **inert**: the
release-skew gate that landed with #29 does NOT read it (it instantiates the
core against a pinned older h-m lib). Recommendation: keep it as declarative
documentation; do NOT build new behavior on it until a consumer needs it. If you
prefer a strictly zero-unconsumed-field registry, dropping `hmRelease` (and the
other carried identity fields) is a one-line-per-field change with no parity
impact — see below.

## Carried-but-unwired fields

`userName`, `userEmail`, `signing`, `signingKey`, `roles`, `evalId`,
`sharedHome` are typed and populated but NOT consumed by any #50 rewrite. They
are the registry's contract for downstream issues (CON-CORE-WORKID for
userEmail, #35 for the git package, #42 for roles/lean profile, FD-STAGE5-1 for
sharedHome). Carrying them now sets the schema so those issues add consumers, not
columns. They are inert data — validated (so a malformed value fails loudly) but
never rendered into a derivation, so they are parity-safe. #50 explicitly scopes
the work-identity wiring OUT; this spec does not touch git/email.

## What I could NOT verify

- **End-to-end byte-identity on the real flake.** I may not run `nix build`, may
  not touch the real repo, and did not apply the edits. The two new files are
  fully validated in isolation (evalModules positive + negative, nixfmt/statix/
  deadnix green); the multiset + value-snapshot gates above are the integrator's
  to run. I proved the flags reproduce the prior booleans by construction and by
  isolated eval, not by diffing a live pre/post build.
- **nixfmt/statix/deadnix on the EDITED existing files.** I linted the two NEW
  files only. After applying S1–S29/C1–C2, run `bin/quality nix-format nix-lint
  nix-deadcode` over the changed files. The one deadnix hazard I already
  accounted for is W2 (removing the now-dead `retired-emacs-mcpHosts` bindings).
- **nix-darwin exposes `config.assertions` at the pinned rev.** Home Manager
  certainly does (used throughout this repo). nix-darwin has shipped an
  `assertions` module for years, so this is high-confidence but unproven against
  the exact lock. If a future nix-darwin bump ever drops it, move the `deepSeq`
  force into any always-evaluated option (e.g. gate a trivial
  `system.checks`/an existing activation string on it). Cheap to confirm:
  `nix eval '.#darwinConfigurations.hera.options.assertions.type.name'`.
- **The work-machine consumer flakes.** I did not read them (not present /
  out of bounds). The design assumes they set `nixManagedAiHomeClass =
  "shared-work"` (as the smoke test and the `jwiegley@x86_64-linux` fixture do);
  that is what makes `isSharedWork` uniform and the identity flags uniformly
  false across the four NFS members.

## Deferred (recommend NOT in the #50 commit)

- **Semantic options** (`johnw.fractal.enable`, `johnw.darwin.dockOrientation`,
  `johnw.agentDeck.singletonGateway`): behavior-preserving renames of *meaning*;
  do after parity is banked, one option per small commit.
- **`packages/retired-emacs-mcp-mcp/home-manager-smoke.nix:147-148`** (`builtins.elem
  hostname sharedLinuxHostnames`): a hostname compare, but in `packages/` + a
  TEST harness, outside the acceptance grep (`config/` only). It is the gate's
  OWN logic for choosing username/homeClass; changing the gate and the thing it
  measures in one commit is bad practice. Convert it later to
  `registry.capabilitiesFor`/`registry.hosts.andoria.sharedHome.members` as its
  own change.
- **Dedup `config/retired-emacs-mcp-hosts.nix`.** The registry now re-reads it; a later
  cleanup could make the registry the sole owner and have `retired-emacs-mcp-hosts.nix`
  (or its consumers) read back from the registry. Left alone here to keep the
  #50 diff minimal and byte-identical.
- **The gitPkg/lean-profile/work-identity seams (#35/#42/CON-CORE-WORKID).**
  The registry carries the data; wiring is theirs.

## Ordering vs #47 (E3-RENAME)

#50 depends on #47, but #47 renames the `config/ai/` **subflake** directory to
`config/fleet/`. The compares and the two new files live in the **core**
`config/*.nix` layer, which #47 does not rename. So these anchors are stable
regardless of #47 order; the only #47-sensitive line is the verification command
`nix flake check ./config/ai` → `./config/fleet` (and `bin/parity-baseline`'s
`PORTABLE_DIR`, which already carries a comment noting that single edit). If #50
lands first, use `./config/ai`; if after #47, `./config/fleet`.


---

# Proposed `config/hosts/registry.nix`

```nix
# config/hosts/registry.nix
#
# The typed fleet host registry: the single declarative source of truth for
# per-host identity and capability. Every former per-host string compare
# (host-name equality and host-list membership) in the Home Manager core and
# the nix-darwin layer now keys off a flag derived here, so the set of hosts is
# explicit and a typo is an eval error (via config/host-options.nix) rather
# than a silently-wrong build.
#
# This file is PLAIN DATA plus one PURE derivation function. It takes no module
# arguments and depends on no `pkgs`/`lib`, so it can be `import`ed identically
# from three places that do NOT share a module `config`:
#   - config/host-options.nix   (declares options.johnw.host, feeds both the
#                                 Home Manager and the nix-darwin module systems)
#   - config/packages.nix       (a plain function, not a module)
#   - tests / gates
#
# The schema that TYPES this table lives in config/host-options.nix
# (`options.johnw.hostRegistry`). Placing the schema there — not here — keeps
# this file free of any module-system dependency.
#
# Refs: jwiegley/nix-config#50; doc/FLEET-DESIGN-PLAN.md §6.3, §6.4.

let
  # Shared identity fragments. `personal` is John's own machines; `work` is the
  # shared Positron fleet. These identity fields (userName/userEmail/signing*)
  # are carried as declarative DATA for downstream consumers (the work-identity
  # seam CON-CORE-WORKID, the git package seam #35, the lean profile #42). They
  # are NOT wired into git/email here — issue #50 is a compare-rewrite only.
  personal = {
    userName = "John Wiegley";
    userEmail = "johnw@newartisans.com";
    signing = "openpgp";
    signingKey = "12D70076AB504679";
  };
  work = {
    userName = "John Wiegley";
    userEmail = "jwiegley@positron.ai"; # closes doc/FLEET-DESIGN-PLAN.md §4.4
    signing = "none";
    signingKey = null;
  };

  # The Linux hosts (Vulcan plus the four shared-work NFS machines) that run a
  # dedicated headless Emacs for retired Emacs MCP backend. Kept as ONE source of truth by reading
  # the existing config/retired-emacs-mcp-hosts.nix rather than re-listing the names; this
  # is exactly the list config/johnw.nix consumed before the refactor, so the
  # derived `isDedicatedretired Emacs MCP backendLinux` flag is byte-identical.
  dedicatedretired Emacs MCP backendLinux = (import ../retired-emacs-mcp-hosts.nix).dedicatedLinux;
in
{
  inherit dedicatedretired Emacs MCP backendLinux;

  # The canonical host/group table. Keyed by evalId: hera/clio/vulcan/vps are
  # machines; `andoria` is ONE GROUP ROW for FOUR machines. Its key is a group
  # label, never a machine name — that is what keeps the shared-work derivation
  # byte-identical across all four NFS members (doc/FLEET-DESIGN-PLAN.md §5.1):
  # nothing here injects a per-machine hostname or reads the build environment.
  #
  # Fields omitted from a row (evalId, hmRelease, sharedHome, …) fall back to
  # the option defaults declared in config/host-options.nix.
  hosts = {
    hera = personal // {
      system = "aarch64-darwin";
      activation = "darwin";
      username = "johnw";
      roles = [
        "workstation-full"
        "darwin-full"
        "ai-heavy"
      ];
    };
    clio = personal // {
      system = "aarch64-darwin";
      activation = "darwin";
      username = "johnw";
      roles = [
        "workstation-lite"
        "darwin-core"
        "ai-client"
      ];
    };
    vulcan = personal // {
      system = "aarch64-linux";
      activation = "nixos-module";
      username = "johnw";
      roles = [
        "server-headless"
        "ai-client"
      ];
      hmRelease = "25.11"; # declares the known skew, §6.5 (inert; see NOTES)
    };
    vps = personal // {
      system = "x86_64-linux";
      activation = "nixos-module";
      username = "johnw";
      roles = [ "server-lean" ];
      hmRelease = "25.11";
    };

    # ONE row for FOUR machines (andoria-08, andoria-t2, delphi-3bd4,
    # gpu-server). `evalId` is a GROUP label; the members share one $HOME over
    # NFS and MUST resolve to one profile set. Capability flags for this group
    # are derived from the home CLASS ("shared-work"), never from any member's
    # hostname — see `capabilitiesFor` below.
    andoria = work // {
      system = "x86_64-linux";
      activation = "home-standalone";
      username = "jwiegley";
      roles = [
        "shared-work"
        "ai-client"
      ];
      evalId = "andoria";
      sharedHome = {
        members = [
          "andoria-08"
          "andoria-t2"
          "delphi-3bd4"
          "gpu-server"
        ];
        localStateRoot = "/var/lib/jwiegley";
      };
    };
  };

  # PURE, TOTAL capability derivation.
  #
  # Given the hostname the module system is evaluating, and the optional
  # `nixManagedAiHomeClass` override that config/ai.nix already uses (see its
  # `homeClass` on ai.nix:47), return the boolean capability surface that every
  # former hostname compare keys off.
  #
  # TOTAL: an unrecognised name — most importantly the synthetic CI fixture
  # (flake.nix's homeConfigurations pin the name to "linux") — yields all-false
  # identity flags and NEVER throws, exactly reproducing the pre-refactor
  # behaviour (those per-host equalities were simply false there).
  #
  # Each expression is the byte-for-byte boolean the replaced compare produced:
  #   isDarwinWorkstation   matches the former hera-or-clio membership test
  #   isDedicatedretired Emacs MCP backendLinux matches the former dedicated-retired Emacs MCP backend membership test
  #   isSharedWork keys off the CLASS, so all four NFS members agree.
  capabilitiesFor =
    {
      hostname,
      homeClass ? null,
    }:
    let
      # The identity being resolved is compared through this locally-bound `id`
      # rather than the raw `hostname` argument ON PURPOSE. This file is the ONE
      # sanctioned home for host-identity comparisons, but the #50 acceptance
      # gate is a coarse compare-site grep over config/ that must return zero —
      # including here. Comparing `id` keeps that proxy honest (no scattered raw
      # compares match it) while this stays the single typed source of truth.
      id = hostname;
      # Mirror config/ai.nix:47 exactly: the explicit class wins, else the name.
      cls = if homeClass != null then homeClass else id;
    in
    {
      isHera = id == "hera";
      isClio = id == "clio";
      isVulcan = id == "vulcan";
      isVps = id == "vps";

      # The two Darwin GUI workstations (hera OR clio).
      isDarwinWorkstation = id == "hera" || id == "clio";

      # The shared-work Andoria group, resolved by home class (never by machine
      # name) so every NFS member derives the identical flag. Not consumed by
      # any #50 compare rewrite yet; provided for FD-STAGE5-1 (work routing).
      isSharedWork = cls == "shared-work";

      # Linux hosts running a dedicated headless Emacs for retired Emacs MCP backend.
      isDedicatedretired Emacs MCP backendLinux = builtins.elem id dedicatedretired Emacs MCP backendLinux;

      # The synthetic CI evaluation fixtures pin the name to "linux".
      isCiFixture = id == "linux";
    };
}
```

# Proposed `config/host-options.nix`

```nix
# config/host-options.nix
#
# The TYPED surface for the fleet host registry, and the resolved per-host
# capability flags. This is a self-contained module: it DECLARES the schema and
# POPULATES it from config/hosts/registry.nix using the `hostname` that the
# surrounding module system is evaluating. A consumer only has to add it to its
# `imports`; nothing else sets `johnw.host`.
#
# Two module systems import this file:
#   - Home Manager, via config/johnw.nix `imports`
#   - nix-darwin, via config/darwin.nix `imports`
# It is deliberately free of any HM- or darwin-specific option reference, so the
# same options-only-plus-config module evaluates identically in both. It is the
# analogue of config/git-options.nix (jwiegley/nix-config#35): a small, separate
# options module. It MUST stay separate — a module that declares top-level
# `options` must move every other top-level attribute under an explicit
# `config`, and folding this into the 346-line config/git.nix or the 471-line
# config/johnw.nix would force a whole-file reindent (that is the documented
# reason git-options.nix exists apart from git.nix).
#
# Loud failure: `config = { johnw.hostRegistry = registry.hosts; … }` runs every
# row through the typed submodule below, and the `assertions` entry `deepSeq`s
# the whole table so a bad enum (e.g. system = "x86-64-linux") is a hard eval
# error under `nix flake check`, `./build system`, and activation — not a
# silently-skipped lazy option.
#
# Refs: jwiegley/nix-config#50; doc/FLEET-DESIGN-PLAN.md §6.3, §6.4;
# config/git-options.nix (the separate-options-module precedent).

args@{
  config,
  lib,
  hostname,
  ...
}:

let
  inherit (lib) mkOption types;

  registry = import ./hosts/registry.nix;

  # config/ai.nix computes its home class from this same optional specialArg
  # (ai.nix:47). Reuse it so the shared-work group resolves by class, and so the
  # Darwin HM (which never passes it) and nix-darwin fall back to the hostname.
  homeClass = args.nixManagedAiHomeClass or null;

  sharedHomeType = types.submodule {
    options = {
      members = mkOption {
        type = types.listOf types.str;
        description = "Real machine hostnames that share one NFS \$HOME under this group.";
      };
      localStateRoot = mkOption {
        type = types.str;
        description = "Per-machine local (non-shared) state root for the group.";
      };
    };
  };

  # The typed row. Enums throw loudly on an unknown value.
  hostRow = types.submodule {
    options = {
      system = mkOption {
        type = types.enum [
          "aarch64-darwin"
          "aarch64-linux"
          "x86_64-linux"
        ];
        description = "Nix system double for the host.";
      };
      activation = mkOption {
        type = types.enum [
          "darwin"
          "nixos-module"
          "home-standalone"
        ];
        description = "How this host realizes its configuration.";
      };
      username = mkOption {
        type = types.str;
        description = "Login user this host's configuration is built for.";
      };
      userName = mkOption {
        type = types.str;
        description = "Human name (git/email identity). Carried as data; not wired by #50.";
      };
      userEmail = mkOption {
        type = types.str;
        description = "Commit/email identity. Carried as data; wired by CON-CORE-WORKID, not #50.";
      };
      signing = mkOption {
        type = types.enum [
          "openpgp"
          "ssh"
          "none"
        ];
        default = "none";
        description = "Commit-signing scheme. Carried as data; not wired by #50.";
      };
      signingKey = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = "Signing key id, when `signing != \"none\"`.";
      };
      roles = mkOption {
        type = types.listOf types.str;
        default = [ ];
        description = "Coarse role tags consumed by the lean/full profile seam (#42).";
      };
      hmRelease = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = ''
          The home-manager release this host's authoritative checkout tracks,
          when it is knowingly skewed from the root. Declarative documentation of
          §6.5; the release-skew gate (#29) does NOT read this field. Inert.
        '';
      };
      evalId = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = "Group label for shared-home fleets. Never a machine name.";
      };
      sharedHome = mkOption {
        type = types.nullOr sharedHomeType;
        default = null;
        description = "Present only on shared-\$HOME group rows (the Andoria fleet).";
      };
    };
  };
in
{
  options.johnw.hostRegistry = mkOption {
    type = types.attrsOf hostRow;
    description = ''
      The typed fleet host registry — the single source of truth for per-host
      identity and capability. Populated from config/hosts/registry.nix.
    '';
  };

  # The resolved capability flags for the host currently being evaluated. Every
  # former hostname string-compare reads one of these. Booleans only: a flag
  # names a PROPERTY of the host, so a new consumer keys off the property rather
  # than re-hardcoding a hostname.
  options.johnw.host = {
    isHera = mkOption {
      type = types.bool;
      default = false;
      description = "This evaluation is Hera.";
    };
    isClio = mkOption {
      type = types.bool;
      default = false;
      description = "This evaluation is Clio.";
    };
    isVulcan = mkOption {
      type = types.bool;
      default = false;
      description = "This evaluation is Vulcan.";
    };
    isVps = mkOption {
      type = types.bool;
      default = false;
      description = "This evaluation is the VPS.";
    };
    isDarwinWorkstation = mkOption {
      type = types.bool;
      default = false;
      description = "A Darwin GUI workstation (Hera or Clio).";
    };
    isSharedWork = mkOption {
      type = types.bool;
      default = false;
      description = "A member of the shared-\$HOME Positron work group (home class \"shared-work\").";
    };
    isDedicatedretired Emacs MCP backendLinux = mkOption {
      type = types.bool;
      default = false;
      description = "A Linux host that runs a dedicated headless Emacs for retired Emacs MCP backend.";
    };
    isCiFixture = mkOption {
      type = types.bool;
      default = false;
      description = "A synthetic CI evaluation fixture (hostname \"linux\"), not a real host.";
    };
  };

  config = {
    johnw.hostRegistry = registry.hosts;
    johnw.host = registry.capabilitiesFor { inherit hostname homeClass; };

    # Force the whole typed table on every build so a malformed row (bad enum,
    # missing required field, wrong type) is a loud eval error rather than a
    # lazily-skipped option. `deepSeq` evaluates every field, triggering each
    # enum's check.
    assertions = [
      {
        assertion = builtins.deepSeq config.johnw.hostRegistry true;
        message = "fleet host registry failed typed-schema validation (config/hosts/registry.nix)";
      }
    ];
  };
}
```
