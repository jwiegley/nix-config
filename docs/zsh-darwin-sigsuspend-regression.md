# zsh-5.9 hangs in `__sigsuspend` on darwin after stdenv source-release migration

## TL;DR

After nixpkgs PR [#508474](https://github.com/NixOS/nixpkgs/pull/508474)
("darwin: migrate source releases from apple-sdk to darwin", merged
2026-04-18, commit `eb059e76`), `zsh-5.9` rebuilds on `aarch64-darwin` /
`x86_64-darwin` produce a binary that **hangs in `__sigsuspend` forever**
when reaping a child of `$(…)` command substitution. The hang is reproducible
in any interactive zsh on macOS — `iTerm2`, `Terminal.app`, and `ssh` from
another host. `bash` is unaffected. `zsh -c …` (no `.zshrc`) is unaffected.
`zsh -ic …` reproduces it. The same `.zshrc` works perfectly with the
pre-rebuild zsh binary still in `/nix/store`.

The root cause is a **build-time autoconf misdetection inside the new darwin
build sandbox**: zsh's `AC_RUN_IFELSE` test program for working
`sigsuspend()` fails to observe `SIGCHLD` and records
`zsh_cv_sys_sigsuspend=no`, which triggers `#define BROKEN_POSIX_SIGSUSPEND`.
That swaps `Src/signals.c:signal_suspend()` from the atomic
`sigsuspend(&saved_mask)` form to a legacy
`sigprocmask(SIG_UNBLOCK,…); pause();` pair. The fallback has a wide race
window between unblock and pause; if `SIGCHLD` arrives in that window — as it
routinely does after a `$(…)` child exits cleanly — its handler runs but
`pause()` then blocks forever waiting for a wakeup that already arrived.

macOS's *actual* `sigsuspend()` works fine outside the sandbox; the binary
still links against `/usr/lib/libSystem.B.dylib`, which still exports
`_sigsuspend`. The problem is that autoconf's *runtime test* misbehaves under
the new stdenv's build sandbox, and the resulting binary embeds the
race-prone code path forever.

## Affected versions

- **nixpkgs**: any revision after `eb059e76` (PR #508474, merged
  ~2026-04-18) that rebuilds zsh against the new darwin stdenv.
  Both `nixpkgs-unstable` and the affected darwin branch of `nixos-unstable`
  ship this regression.
- **zsh source**: 5.9 (unmodified upstream; the bug is in the configure-time
  detection, not in zsh's source).
- **OS**: macOS 26.4.1 build `25E253` confirmed (Apple Silicon, kernel
  Darwin `25.4.0`, `xnu-12377.101.15~1`, `T6031`). Almost certainly affects
  earlier macOS versions on this stdenv too — the sandbox-side test failure
  isn't macOS-version-specific.
- **Architectures**: confirmed `aarch64-darwin`. Likely also affects
  `x86_64-darwin` since the regression is in the build environment, not the
  target.
- **Not affected**: Linux hosts (the test passes there), and pre-`eb059e76`
  builds of zsh-5.9 on darwin still in any user's nix store.

## Reproduction

On a darwin host whose nix-darwin / home-manager generation was rebuilt after
the PR, with any non-empty interactive `.zshrc`:

```sh
# 1. Non-interactive (no .zshrc) -- WORKS
zsh -c 'echo OK'

# 2. Interactive (sources .zshrc) -- HANGS
zsh -ic 'echo OK'

# 3. Bash (control) -- WORKS
bash -ic 'echo OK'
```

The interactive case hangs indefinitely (no SIGINT response, ignores the
keystroke, ignores the next-prompt redraw) the *first time it is forced into
a `$(…)` reaping race*. Common triggering call sites observed in the wild:

- `eval "$(starship init zsh)"` (zsh init phase)
- `eval "$(direnv hook zsh)"` (precmd hook)
- `$(hostname -f 2>/dev/null)` inside iTerm2 shell-integration's
  `iterm2_print_state_data` (every prompt on macOS, since the iTerm2 plugin
  intentionally doesn't cache the FQDN there).

## Diagnostic fingerprints

The hang is identifiable from outside the stuck process via four
near-deterministic signals:

1. **`sample` stack**:
   ```
   …preprompt → callhookfunc → doshfunc → … → execif → … →
     prefork → getoutput → waitforpid → signal_suspend → pause → __sigsuspend
   ```
   Note the `pause` frame above `__sigsuspend` — that's the broken userspace
   code path, not the safe atomic one. (macOS implements `pause(3)` as
   `sigsuspend(0)`, which is why `__sigsuspend` is at the bottom even on the
   broken build.)

2. **`ps`**: the stuck zsh has *no child process* in the tree (neither
   running nor zombie). The `$(…)` subprocess already exited.

3. **`lsof -p <zsh-pid>`**: the command-substitution pipe FD shows
   `PIPE 0x… 16384` with no peer — the child's writer end is closed, only
   zsh's reader end remains.

4. **`nm -u $(command -v zsh) | grep -E '_(sigsuspend|pause)$'`**: the
   broken build imports `_pause`. A correctly built zsh imports
   `_sigsuspend`. This is the most direct diagnostic and works on any
   binary, no need to attach to a running process.

## Root-cause walkthrough

The `nix log` for the affected zsh derivation shows the configure-time
verdict:

```
checking if POSIX sigsuspend() works... no
```

Compare to a pre-PR build of the *same source*:

```
checking if POSIX sigsuspend() works... yes
```

The relevant chunk of `configure.ac` (zsh-5.9 line 2331-2366):

```m4
AH_TEMPLATE([BROKEN_POSIX_SIGSUSPEND],
[Define to 1 if sigsuspend() is broken, ie BeOS R4.51.])
if test x$signals_style = xPOSIX_SIGNALS; then
    AC_CACHE_CHECK(if POSIX sigsuspend() works,
    zsh_cv_sys_sigsuspend,
    [AC_RUN_IFELSE([AC_LANG_SOURCE([[
#include <signal.h>
#include <unistd.h>
#include <stdlib.h>
int child=0;
void handler(sig) int sig;
{if(sig==SIGCHLD) child=1;}
main() {
    struct sigaction act;
    int pid, ret;
    sigset_t set;
    act.sa_handler = handler;
    sigemptyset(&act.sa_mask);
    act.sa_flags = 0;
    sigaction(SIGCHLD, &act, NULL);
    pid = fork();
    if(pid==0) exit(0);
    if(pid>0) {
        sigemptyset(&set);
        ret=sigsuspend(&set);
        exit(child==0);
    }
}
]])],[zsh_cv_sys_sigsuspend=yes],[zsh_cv_sys_sigsuspend=no],
   [zsh_cv_sys_sigsuspend=yes])])
    if test x$zsh_cv_sys_sigsuspend = xno; then
      AC_DEFINE(BROKEN_POSIX_SIGSUSPEND)
    fi
fi
```

Outside the sandbox, this program forks, the child exits, the parent's
`SIGCHLD` handler fires, `child` is set to 1, and the program exits 0
(success). Inside the new darwin build sandbox it returns nonzero — the
`SIGCHLD` is not observed by the parent's handler in the
`fork() → exit() → sigsuspend()` window.

`Src/signals.c:signal_suspend()` then takes the `BROKEN_POSIX_SIGSUSPEND`
branch (lines 371, 388-394 in zsh-5.9), which is the legacy
`sigprocmask(SIG_UNBLOCK,…) + pause()` pair. That pair has a textbook
TOCTOU-style race: between `sigprocmask` unmasking `SIGCHLD` and `pause()`
blocking, a `SIGCHLD` from an *already-exited* child can fire its handler
(updating zsh's job-table bookkeeping) and then `pause()` waits forever for
*another* signal that never comes. POSIX added `sigsuspend()` precisely to
close this race; the entire reason zsh probes for it is to use the safe
form when available.

Symbol-level confirmation:

| Build                                        | imports        |
|----------------------------------------------|----------------|
| pre-PR-#508474 (`2sbihdb…-zsh-5.9`)          | `_sigsuspend`  |
| post-PR-#508474 (`80qadsn…-zsh-5.9`)         | `_pause`       |

Same upstream version, same `Src/signals.c` source, different code path
compiled in.

## Why the sandbox test fails (open question)

I have not fully bisected *which specific aspect* of the new darwin stdenv
changes how `sigaction(SIGCHLD)` + `fork()` + `sigsuspend(&empty_set)`
behave. Plausible candidates:

- New sandbox profile in the `eb059e76` rework masks or rewrites
  `SIGCHLD` delivery between sandbox-internal processes.
- Restricted `posix_spawn`-style fork path through the new stdenv's
  `nixbld`/`/nix/store/.../bash` builder differs from the previous
  `apple-sdk`-rooted bash, and child-process accounting changes.
- A change in feature-test macros from the new SDK headers
  (`_DARWIN_C_SOURCE`, `_POSIX_C_SOURCE`) alters which `sigaction` flags
  default to set, e.g. `SA_NOCLDWAIT` defaulting on for the test program's
  context.

The runtime test running on the *user's* machine outside the sandbox works
correctly — the same `_sigsuspend` symbol is in `libSystem.B.dylib` and the
syscall behaves as POSIX requires. So the bug isn't in macOS or in zsh's
source; it's a sandbox-vs-real-kernel-behavior discrepancy that causes
autoconf to make the wrong determination and bake the wrong code path into
the binary.

## Workaround

Add a small overlay that pre-populates the autoconf cache with the value
the test would compute outside the sandbox:

```nix
# overlays/zsh-fix.nix
final: prev: {
  zsh = prev.zsh.overrideAttrs (oldAttrs:
    prev.lib.optionalAttrs prev.stdenv.isDarwin {
      preConfigure = (oldAttrs.preConfigure or "") + ''
        export zsh_cv_sys_sigsuspend=yes
      '';
    });
}
```

This bypasses the broken sandbox-side runtime test and produces a zsh that
links against `_sigsuspend` and uses the atomic, race-free
`signal_suspend()` path. Verified by:

1. `nix log <zsh.drv>` → `checking if POSIX sigsuspend() works... (cached) yes`
2. `nm -u $(command -v zsh)` → shows `_sigsuspend`, no `_pause`
3. `time timeout 5 zsh -ic 'echo OK'` → returns successfully in <3s
4. Fresh interactive shells stop hanging on prompt redraws.

## Suggested upstream fix

Two reasonable paths:

1. **Add the workaround to nixpkgs' zsh package** as a darwin-conditional
   `preConfigure` (same shape as above) until the sandbox-test discrepancy
   is understood and resolved at the stdenv level. This trades a minor
   degradation (skipping the runtime probe) for correctness on every
   affected build.

2. **Fix the underlying sandbox-side signal-delivery discrepancy** so the
   runtime test correctly returns "yes". This requires investigation of
   what changed in PR #508474 — likely a sandbox profile, builder shell, or
   feature-test macro — and is the more durable fix.

(1) is mechanically easy and unblocks every affected user immediately. (2)
is preferable long-term because there are likely *other* `AC_RUN_IFELSE`
probes in *other* darwin packages that are silently failing in the same
way.

## Where to file this

**Primary venue: [github.com/NixOS/nixpkgs Issues](https://github.com/NixOS/nixpkgs/issues/new/choose)** — nixpkgs owns the `zsh` derivation, the darwin stdenv, and PR #508474 itself. Use the **"Bug report"** template (not "Build failure" — the build succeeds; the regression is at runtime). Apply labels `0.kind: bug`, `0.kind: regression`, `6.topic: darwin`, `6.topic: zsh`. Cross-reference PR #508474 in the body and ping its reviewers/author plus `@NixOS/darwin-maintainers`.

Suggested title:

> `zsh: sigsuspend autoconf probe fails in new darwin stdenv sandbox (post #508474), causing SIGCHLD races / interactive hangs`

Before filing, search for existing issues to avoid duplicating:

- https://github.com/NixOS/nixpkgs/issues?q=is%3Aissue+zsh+sigsuspend
- https://github.com/NixOS/nixpkgs/issues?q=is%3Aissue+BROKEN_POSIX_SIGSUSPEND
- https://github.com/NixOS/nixpkgs/pulls?q=zsh+sigsuspend
- The PR's own conversation: https://github.com/NixOS/nixpkgs/pull/508474

**Secondary cross-links** (after the primary issue exists, so they can link to it):

- **[LnL7/nix-darwin Issues](https://github.com/LnL7/nix-darwin/issues)** — short pointer issue ("tracking nixpkgs#NNN"). Users hitting wedged interactive shells via `programs.zsh` are likely to look here first.
- **[NixOS Discourse — Help category](https://discourse.nixos.org/c/help/6)** — post tagged `darwin`, `macos`, `zsh`. There is no dedicated darwin sub-category. Search first: https://discourse.nixos.org/search?q=zsh%20sigsuspend%20darwin
- **Matrix `#darwin:nixos.org`** — https://matrix.to/#/#darwin:nixos.org — drop a heads-up linking the GitHub issue. `#macos:nixos.org` is also relevant.

**Skip for now: zsh-workers (`zsh-workers@zsh.org`).** The `signal_suspend()` fallback race exists in upstream zsh, but it's only being triggered because nixpkgs' build sandbox misdetects sigsuspend. macOS's sigsuspend itself works. This is a build-environment bug, not an upstream zsh defect. Only escalate to zsh-workers if you want to propose hardening the fallback path itself — in which case reference `Src/signals.c` and `configure.ac:2334-2362` and CC Bart Schaefer / Peter Stephenson.

## References

- nixpkgs PR #508474 — https://github.com/NixOS/nixpkgs/pull/508474
- zsh `Src/signals.c` (`signal_suspend`) — https://github.com/zsh-users/zsh/blob/master/Src/signals.c
- zsh `configure.ac` (sigsuspend probe) — https://github.com/zsh-users/zsh/blob/master/configure.ac
- Red Hat KB 2720181 (related upstream zsh `getoutput` SIGCHLD race) —
  https://access.redhat.com/solutions/2720181
- Apple Developer Forum #134003 (macOS sigsuspend/SIGCHLD POSIX
  non-compliance, FB7731811) —
  https://developer.apple.com/forums/thread/134003

## Reporter environment

- nix-darwin, home-manager, flakes
- Two affected hosts: `aarch64-darwin` running macOS 26.4.1
- Boundary: nix-darwin generation rebuild dated 2026-04-24 17:21 (host A)
  and 2026-04-25 (host B); both rebuilds switched zsh from store path
  `2sbihdbgf5wvyd4a72x8k1ism55z8ccx-zsh-5.9` (working) to
  `80qadsnhhrfkh6aidp9aa49my6hnd1dr-zsh-5.9` (broken).
- Closure diff at the boundary: `apple-sdk` added (+354 MiB), zsh + pcre2
  + ncurses + libiconv all rebuilt with same versions but new hashes —
  the canonical fingerprint of an stdenv-level rebuild.
