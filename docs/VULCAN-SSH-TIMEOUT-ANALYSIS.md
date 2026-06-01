# Vulcan SSH Timeout — Root-Cause Analysis & Fix Options

**Date:** 2026-05-31
**Investigating host:** `clio` (macOS, `en0 = 192.168.3.9`)
**Target:** `vulcan` (NixOS / Asahi, dual-homed)
**Status:** Root cause **confirmed and adversarially verified** (0/3 skeptics could refute it; the decisive experiment reproduced **7/7**). No fix applied yet — this document is for review before changing config.

---

## TL;DR

- The `vulcan` SSH alias hardcodes `HostName = 192.168.1.2` (`config/ssh.nix:107`), which is vulcan's **wired** NIC on a **different subnet** from clio.
- This forces an **asymmetric route**: the connection goes out via the gateway `192.168.3.1`, but vulcan's replies come *directly back* out its **WiFi** NIC `192.168.3.16` — so the gateway only ever sees half the flow and its stateful conntrack entry expires after ~60 s idle, silently dropping the session. Initial-connect resets and WiFi-return stalls ride the same broken topology.
- The earlier "fix" (commit `10a2617`, keepalives) operates on an *already-established* session only. It genuinely rescues the idle-drop case **but cannot touch** initial-connect resets or the asymmetric path — which is why timeouts persist.
- **Because clio roams between the `192.168.1.x` (upstairs) and `192.168.3.x` (downstairs) subnets, no single static IP is correct.** The right fix is OpenSSH `Match exec` to pick vulcan's **same-segment** address at connect time — collapsing every connection to a direct, symmetric, single L2 hop.

---

## 1. The Problem

SSH connections to `vulcan` intermittently time out. A prior change was believed to fix this but did not. The failures are **intermittent / state-dependent** — at the time of investigation, fresh connections, full handshakes, and 1500-byte MTU all succeeded on both addresses, so this is not a hard always-fail.

---

## 2. Topology (the root of it all)

`vulcan` is **one physical machine** (single ed25519 host key
`SHA256:eOmtKS8ImWRkNmCQsKKJRpMBtqVfTUah5sZiAd+pFos` on both addresses) that is **dual-homed across two subnets**:

| Interface | Address | Reverse DNS | Relationship to clio (`.3.9`) |
|-----------|---------|-------------|-------------------------------|
| `end0` (wired) | `192.168.1.2` | `vulcan` | **Different** subnet — reached via gateway `192.168.3.1` (routed, no direct ARP) |
| `wlp1s0f0` (WiFi, Broadcom `brcmfmac`) | `192.168.3.16` | `vulcan-wifi` | **Same** segment — direct ARP `9c:76:0e:33:bd:90`, L2-adjacent |

```
                       ssh vulcan  (HostName 192.168.1.2)
  clio .3.9  ── SYN ──►  gateway 192.168.3.1  ── routed ──►  vulcan end0 (.1.2)  [wired]
      ▲                                                              │
      │                                                              │ reply to .3.9 is a
      └──────────────  direct via WiFi  ◄───────────────────────────┘ CONNECTED route only
                       vulcan wlp1s0f0 (.3.16)                         on wlp1s0f0  → egresses WiFi

  FORWARD = routed through the gateway      RETURN = direct out WiFi, bypassing the gateway
  ⇒ ASYMMETRIC: the gateway sees only the forward half of every flow.
```

`ip route get 192.168.3.9` on vulcan (even `from 192.168.1.2`) returns `dev wlp1s0f0` — replies to clio **always** leave the WiFi NIC, because `192.168.3.0/24` is a connected route only there.

---

## 3. The Proof (controlled experiment)

A 75-second **idle** SSH session with keepalives **off**, run against each address:

| Path | Address | 75 s idle, keepalive OFF | Trials |
|------|---------|--------------------------|--------|
| Routed / cross-subnet | `192.168.1.2` | **DROPPED** (`Operation timed out` / `Broken pipe`, rc=255) | 7 / 7 fail |
| Same-segment / direct | `192.168.3.16` | **SURVIVED** (rc=0) | 7 / 7 pass |

(7 total trials across three independent adversarial verifiers.)

- **Idle-drop threshold** on the routed path: 40 s / 45 s / 60 s **survive**, 65–75 s **drop** ⇒ a stateful idle-timeout of ~60 s exists **only** on the `.1.2` path.
- **The path, not the client, decides the outcome.** Same client settings; only the address differs.
- The ~60 s dropper is **not** vulcan's own conntrack (its established timeout is 432000 s; table ~1.5k/262k, far from exhausted) and there is **no NAT** (vulcan sees clio's real `.3.9` source on both paths). By elimination it is the **gateway `192.168.3.1`**, which only the `.1.2` flow traverses.
- **MTU is identical** (1500) on both paths — no PMTU blackhole.
- Live transient failures captured during scouting on the `.1.2` path: `kex_exchange_identification: read: Connection reset by peer` and `Connection closed by 192.168.1.2 port 22` — these are **initial-connect** (pre-auth) failures.

---

## 4. Why the prior keepalive fix could not have worked

Commit **`10a2617`** ("Change SSH KeepAlive for connections to Vulcan", 2026-05-25) added only:

```nix
ServerAliveInterval = 30;
ServerAliveCountMax = 6;
TCPKeepAlive = true;
```

These operate at exactly **one** layer: generating traffic on an **already-established, authenticated** channel to keep a middlebox flow warm and detect a dead peer.

- It **does** work for that one case — a 75 s idle session *with* these settings **survives** the routed path (verified). The fix is not inert.
- But the residual timeouts live at layers keepalives structurally cannot reach:
  1. **Initial-connect resets** (`kex_exchange_identification …`) happen *before* auth — there is no established channel for a keepalive to fire on. And `ConnectTimeout` is currently `none`, so a hung initial connect never self-aborts.
  2. **The asymmetric path / gateway idle-expiry** — keepalives *mask* the drop by refreshing the flow every 30 s, but never remove the trigger; a WiFi-return micro-stall or a moment where the keepalive itself can't be delivered still kills it.

It changed `HostName`? No. Added `ProxyJump`? No. Set `ConnectTimeout`? No. It patched the symptom layer, not the path.

---

## 5. Secondary findings

- **A prior network-layer fix is silently a no-op.** `vulcan:/etc/nixos/modules/core/networking.nix` defines an `asymmetric-routing` systemd service + NetworkManager routing-rules meant to install `ip rule … table end0_return` (priority 50/51). At runtime `ip rule show` contains **only** the stock rules (0 / 32766 / 32767); table 200 is populated but **never consulted**. Every `ip rule add` is masked with `|| true`, and the NM profile races the service. The service reports `active` while doing nothing — likely why this felt "already fixed."
  - Note: even if those rules *were* installed, they only steer traffic *sourced from* `192.168.1.2`; replies *destined to* `192.168.3.x` still match the connected `wlp1s0f0` route, so they likely could **not** move clio's replies off WiFi anyway.
- **Split-brain DNS.** Forward `vulcan` / `vulcan.lan` → `192.168.3.16` (WiFi), but the SSH alias + reverse DNS of `.1.2` + `gitea` + `router` → `192.168.1.2` (wired). Interactive SSH and build/service traffic (nix remote-builder, litellm, HA) take **different physical paths** to the same box.
- **`rp_filter` is loose (2) by accident.** Loose reverse-path filtering is the *only* reason the asymmetric return isn't dropped at vulcan today. A future NixOS/NM/reboot flip to strict (`1`) would silently convert the intermittent timeout into a **hard, total** failure for `.3.x` clients. `firewall.checkReversePath = false` is present in the config **but commented out** (with a comment noting it's "Required for asymmetric routing between WiFi and Ethernet").
- **WiFi power management is nominally enabled** on `wlp1s0f0` (`power/control=on`; NM `powersave` unset/default), and the `brcmfmac` driver is documented-flaky under load. That interface carries the return leg of **every** clio↔vulcan session regardless of which IP is dialed. Currently pristine (quality 70/70, −37 dBm, zero deauth/brcmfmac events over 10+ days) — a **latent** risk, not the active fault.
- **`gitea` pins the same cross-subnet IP** (`192.168.1.2:2222`) and would benefit from the same treatment.

---

## 6. Recommended fix — dynamic, roaming-aware addressing (`Match exec`)

Because **clio roams** between `.1.x` (upstairs) and `.3.x` (downstairs), a static per-host IP is wrong. OpenSSH's `Match exec` (supported by clio's OpenSSH 10.3) runs a shell probe at connect time and selects vulcan's **same-segment** address for whatever subnet clio is currently on. Every connection then becomes a **direct, symmetric, single L2 hop** — eliminating the gateway asymmetry entirely, in any location.

### Generated `~/.ssh/config`

```sshconfig
Host vulcan
    User johnw
    IdentityFile ~/clio/id_clio
    IdentitiesOnly yes
    ConnectTimeout 15                 # bound hung initial connects (was: none)
    ControlMaster auto
    ControlPath ~/.ssh/sockets/%C
    ControlPersist 1800
    Compression no
    ForwardAgent yes
    ServerAliveInterval 30            # defense-in-depth, NOT the fix
    ServerAliveCountMax 6
    TCPKeepAlive yes
    RemoteForward [localhost]:8317 [127.0.0.1]:8317
    # deliberately NO HostName here — chosen dynamically below

# downstairs / on the .3 segment → vulcan's same-segment WiFi address (direct L2 hop)
Match originalhost vulcan exec "/sbin/ifconfig | grep -q 'inet 192.168.3.'"
    HostName 192.168.3.16

# upstairs / on the .1 segment → vulcan's same-segment wired address (direct L2 hop)
Match originalhost vulcan exec "/sbin/ifconfig | grep -q 'inet 192.168.1.'"
    HostName 192.168.1.2

# off-LAN fallback (unreachable anyway; keeps ssh from dialing the literal name)
Match originalhost vulcan
    HostName 192.168.3.16
```

OpenSSH uses **first-obtained-value** per keyword: whichever `Match` fires first sets `HostName`; the unconditional fallback must be last.

### Why it's robust + edge cases

- **`originalhost vulcan`** matches the alias as typed (`ssh vulcan`) *before* `HostName` substitution, so the gate still works even though the block rewrites `HostName`.
- **Roaming + ControlMaster:** `%C` hashes the resolved `HostName`, so `.3.16` and `.1.2` get **separate** master sockets — roaming upstairs opens a fresh master for the new segment rather than reusing a stale one. (An old master may linger up to `ControlPersist` = 30 min, harmless; `ssh -O exit vulcan` clears it.)
- **Both subnets at once** (Ethernet `.1` + WiFi `.3`): the `.3` rule wins. Swap the first two blocks to prefer wired.
- **Off the home LAN** (coffee shop / VPN): neither exec matches → fallback. vulcan is a LAN host, unreachable off-net regardless. *If a Tailscale/WireGuard path exists, add a `Match` for it.*
- **Cross-platform:** gate the stanza to Darwin (`vars.isDarwin`) so the macOS `ifconfig` probe never runs on the NixOS/Ubuntu hosts (which don't roam and can't reach vulcan's LAN anyway).
- **`Match exec` cost:** one `ifconfig | grep` per `ssh vulcan` (and per `ssh -G vulcan`) — negligible.

### Wiring it into `config/ssh.nix` (two options)

1. **Raw `extraConfig` stanza (recommended).** Remove `HostName` from the structured `vulcan` block and emit the three `Match` lines as raw text, so their order is fully controlled (independent of how the module sorts blocks). The `"*"` block is already declared, which `extraConfig` requires. Since nothing else sets vulcan's `HostName`, the `Match` lines win cleanly.
2. **Per-block `header`.** Express each `Match` as its own `settings` entry using the same `header =` field the `positron`/`savannah` blocks use, ordered with `lib.hm.dag.entryBefore`.

> Always `./build system` to confirm the emitted config before any `u switch`.

---

## 7. Alternatives considered (and why rejected)

| Approach | Verdict |
|----------|---------|
| **Static per-host IP** (clio→`.3.16`, hera→`.1.2`, keyed on `hostname`) | **Rejected** — clio *roams*, so a single static IP is wrong half the time. |
| **mDNS `vulcan.local`** | **Rejected** — resolves to whatever interface advertises and won't *prefer* the same-segment address; `.1.2` is reachable from both subnets so it never picks the direct path. |
| **Multi-A DNS record** (`vulcan.lan` → both IPs) | **Rejected** — ssh tries addresses in DNS order; `.1.2` is always reachable (routed), so it'd be chosen first → asymmetry persists. Doesn't prefer same-segment. |
| **Split-horizon DNS** (per-VLAN views) | **Rejected** — fragile; depends on separate DNS per location; current DNS is already inconsistent. |
| **Fix asymmetry on vulcan** (working policy routing) | **Rejected as primary** — `192.168.3.0/24` is a connected route only on WiFi, so even correct `ip rule`s can't move `.3.x`-destined replies off `wlp1s0f0`. Can't fully symmetrize the clio pairing without re-architecting the network. |
| **`Match exec` same-segment selection** | **Chosen** — native, deterministic, handles roaming, yields a direct symmetric hop in every location. |
| **Wired re-architecture** (clio + a vulcan iface on one segment) | Best long-term robustness, but needs physical/network changes — out of scope for a config fix. |

---

## 8. Supporting deliverable — monitoring / reproduction harness

Leave this running on clio for hours/days. Every cycle it pings both addresses, runs a bounded full handshake to both IPs **and** the alias, and (periodically) runs the 75 s idle-drop reproduction. On **any** failure it snapshots route/arp/ifconfig/`ssh -G` so the next intermittent timeout is captured with full client state. The log signature tells you which root cause fired.

**Suggested path:** `~/bin/vulcan-watch.sh`

```bash
#!/usr/bin/env bash
# vulcan-watch.sh - unattended intermittent-ssh-timeout catcher for clio -> vulcan
# Leave running for hours/days. Catches the next timeout WITH full client state.
#
# Logs:    ~/vulcan-watch.log            (one line per probe, timestamped)
# Snaps:   ~/vulcan-watch-snaps/<ts>.txt (route/arp/ifconfig/ssh-G on every FAIL)
#
# Root-cause signatures (see "what it proves"):
#   RC1 asymmetric routed path: IDLE-.1.2 FAILs while IDLE-.3.16 + ping-both PASS.
#   RC2 WiFi return-path stall:  ping-.3.16 loss / HS-.3.16 FAIL with .1.2 also degraded.
#   RC initial-connect reset:    HS-* FAIL with 'kex_exchange_identification'/'reset'.
set -u

ID=/Users/johnw/clio/id_clio
WIRED=192.168.1.2
WIFI=192.168.3.16
ALIAS=vulcan
USER=johnw
INTERVAL="${INTERVAL:-20}"        # seconds between cycles
IDLE_SECS="${IDLE_SECS:-75}"      # idle-drop reproduction window (>60s triggers RC1)
IDLE_EVERY="${IDLE_EVERY:-9}"     # run the slow idle probe every Nth cycle
LOG="${LOG:-$HOME/vulcan-watch.log}"
SNAPDIR="${SNAPDIR:-$HOME/vulcan-watch-snaps}"
mkdir -p "$SNAPDIR"

ts(){ date '+%Y-%m-%dT%H:%M:%S%z'; }
log(){ printf '%s %s\n' "$(ts)" "$*" >> "$LOG"; }
now_ms(){ perl -MTime::HiRes=time -e 'printf "%d", time()*1000'; }

SSH_COMMON=(-o BatchMode=yes -o ConnectTimeout=8 -o ControlMaster=no \
  -o ControlPath=none -o StrictHostKeyChecking=accept-new \
  -o IdentitiesOnly=yes -i "$ID")

# Bounded handshake probe. $1=label $2=target(ip|alias).
handshake(){
  local label="$1" tgt="$2" dest rc t0 t1 out
  case "$tgt" in
    "$ALIAS") dest="$ALIAS" ;;            # let ssh_config resolve the alias
    *)        dest="${USER}@${tgt}" ;;
  esac
  t0=$(now_ms)
  out=$(timeout 15 ssh "${SSH_COMMON[@]}" \
        -o ServerAliveInterval=5 -o ServerAliveCountMax=2 \
        "$dest" true 2>&1)
  rc=$?
  t1=$(now_ms)
  if [ "$rc" -eq 0 ]; then
    log "HS   $label PASS ${tgt} $((t1-t0))ms"
  else
    log "HS   $label FAIL ${tgt} $((t1-t0))ms rc=$rc :: ${out//$'\n'/ | }"
  fi
  return $rc
}

# Long idle probe, keepalives OFF, to provoke RC1 gateway idle-drop. $1=label $2=ip
idle_probe(){
  local label="$1" ip="$2" rc out t0 t1
  t0=$(now_ms)
  out=$(timeout $((IDLE_SECS+25)) ssh "${SSH_COMMON[@]}" \
        -o ServerAliveInterval=0 -o TCPKeepAlive=no \
        "${USER}@${ip}" "sleep ${IDLE_SECS}; echo ok" 2>&1)
  rc=$?
  t1=$(now_ms)
  if [ "$rc" -eq 0 ] && printf '%s' "$out" | grep -q ok; then
    log "IDLE $label PASS ${ip} $((t1-t0))ms (${IDLE_SECS}s idle, keepalive OFF)"
  else
    log "IDLE $label FAIL ${ip} $((t1-t0))ms rc=$rc :: ${out//$'\n'/ | }"
  fi
  return $rc
}

# ICMP probe. $1=label $2=ip.
ping_probe(){
  local label="$1" ip="$2" out loss rtt
  out=$(ping -c 3 -t 5 "$ip" 2>&1)
  loss=$(printf '%s' "$out" | sed -n 's/.* \([0-9.]*\)% packet loss.*/\1/p' | head -1)
  rtt=$(printf '%s' "$out"  | sed -n 's#.* = [0-9.]*/\([0-9.]*\)/.*#\1#p' | head -1)
  : "${loss:=100}"; : "${rtt:=NA}"
  if [ "$loss" = "0.0" ] || [ "$loss" = "0" ]; then
    log "PING $label PASS ${ip} loss=${loss}% avg=${rtt}ms"
  else
    log "PING $label FAIL ${ip} loss=${loss}% avg=${rtt}ms"
  fi
}

snapshot(){
  local why="$1" f="$SNAPDIR/$(date '+%Y%m%dT%H%M%S').txt"
  {
    echo "# SNAPSHOT $(ts)  reason: $why"
    echo "## route get $WIRED";  route -n get "$WIRED"  2>&1
    echo "## route get $WIFI";   route -n get "$WIFI"   2>&1
    echo "## ssh -G $ALIAS"; ssh -G "$ALIAS" 2>&1 | grep -Ei '^(hostname|identityfile|connecttimeout|serveralive|tcpkeepalive|controlmaster|controlpersist) '
    ahost=$(ssh -G "$ALIAS" 2>/dev/null | awk '/^hostname /{print $2; exit}')
    [ -n "${ahost:-}" ] && { echo "## route get (alias HostName $ahost)"; route -n get "$ahost" 2>&1; }
    echo "## arp -an";        arp -an 2>&1
    echo "## ifconfig en0";   ifconfig en0 2>&1
    echo "## scutil --dns";   scutil --dns 2>&1 | sed -n '1,40p'
    echo "## netstat -rn";    netstat -rn 2>&1 | grep -E 'default|192.168'
    echo "## control sockets"; ls -la "$HOME/.ssh/sockets" 2>&1
  } > "$f"
  log "SNAP written $f ($why)"
}

log "START vulcan-watch interval=${INTERVAL}s idle=${IDLE_SECS}s every=${IDLE_EVERY} wired=${WIRED} wifi=${WIFI}"
trap 'log "STOP vulcan-watch"; exit 0' INT TERM

cycle=0
while :; do
  cycle=$((cycle+1)); fail=0
  ping_probe wired "$WIRED" || fail=1
  ping_probe wifi  "$WIFI"  || fail=1
  handshake  wired "$WIRED" || fail=1
  handshake  wifi  "$WIFI"  || fail=1
  handshake  alias "$ALIAS" || fail=1
  if [ $((cycle % IDLE_EVERY)) -eq 0 ]; then
    idle_probe wired "$WIRED" || fail=1
    idle_probe wifi  "$WIFI"  || fail=1
  fi
  [ "$fail" -ne 0 ] && snapshot "probe-failure cycle=$cycle"
  sleep "$INTERVAL"
done
```

**Run it:**

```bash
chmod +x ~/bin/vulcan-watch.sh
nohup ~/bin/vulcan-watch.sh >/dev/null 2>&1 &   # survives logout
tail -f ~/vulcan-watch.log                      # watch live
ls ~/vulcan-watch-snaps/                        # per-incident state captures
pkill -f vulcan-watch.sh                         # stop
# tune: INTERVAL=20 IDLE_SECS=75 IDLE_EVERY=9 nohup ~/bin/vulcan-watch.sh &
```

**What the log proves:**

- **RC1 (asymmetric routed path — primary):** `IDLE wired FAIL 192.168.1.2 … rc=255` near ~60–105 s while `IDLE wifi PASS`, `PING wired PASS`, `PING wifi PASS` ⇒ gateway stateful-idle expiry on the half-visible flow.
- **Initial-connect reset:** `HS * FAIL … kex_exchange_identification` / `reset by peer` at rc=255 on a fresh handshake (no session existed) ⇒ the layer keepalives can't reach.
- **RC2 (WiFi return-path stall — currently dormant):** `PING wifi FAIL` / `HS wifi FAIL` coincident with `.1.2` also degrading (both share the WiFi return NIC).
- **Alias vs IP:** comparing `HS alias` against `HS wired`/`HS wifi` shows which physical path the alias currently selects — validating the fix actually moved the alias onto the symmetric same-segment path.

---

## 9. Supporting deliverable — regression test

Run on clio after `u switch`. Fails if the config regresses toward the asymmetric cross-subnet path or loses the bounded-connect / idle-survival guarantees. Roaming-aware: it asserts the alias resolves to a **same-segment** address for *whatever* subnet clio is currently on.

**Suggested path:** `~/bin/regress-vulcan-path.sh`

```bash
#!/usr/bin/env bash
# regress-vulcan-path.sh -- fails if vulcan ssh path regresses to asymmetric/cross-subnet.
set -u
ID=/Users/johnw/clio/id_clio
USER=johnw
fail(){ echo "REGRESS FAIL: $*" >&2; exit 1; }

# This client's current segment (en0 /24 prefix, e.g. 192.168.3)
myip=$(ipconfig getifaddr en0) || fail "no en0 IPv4"
myprefix=${myip%.*}

# 1) Alias must resolve to a HostName on THIS client's segment (not cross-subnet).
ahost=$(ssh -G vulcan 2>/dev/null | awk '/^hostname /{print $2; exit}')
[ -n "$ahost" ] || fail "ssh -G vulcan returned no hostname"
if printf '%s' "$ahost" | grep -qE '^[0-9.]+$'; then ahip="$ahost"
else ahip=$(dscacheutil -q host -a name "$ahost" | awk '/ip_address/{print $2; exit}'); fi
[ -n "${ahip:-}" ] || fail "could not resolve vulcan HostName '$ahost'"
[ "${ahip%.*}" = "$myprefix" ] || \
  fail "vulcan -> $ahip is NOT on this client's segment $myprefix.0/24 (asymmetric path regressed)"

# 2) Route to that address must be DIRECT (no gateway) = symmetric single hop.
route -n get "$ahip" 2>/dev/null | grep -q 'gateway:' && \
  fail "route to $ahip traverses a gateway (asymmetric routed path), expected direct L2"

# 3) ConnectTimeout must be bounded so hung initial connects self-abort.
ct=$(ssh -G vulcan 2>/dev/null | awk '/^connecttimeout /{print $2; exit}')
{ [ -n "$ct" ] && [ "$ct" != "none" ] && [ "$ct" -gt 0 ] 2>/dev/null; } || \
  fail "ConnectTimeout is unbounded ('$ct')"

# 4) Idle survival: 75s idle, keepalives OFF, must survive on the chosen address.
out=$(timeout 110 ssh -o BatchMode=yes -o ConnectTimeout=8 -o ControlMaster=no \
      -o ControlPath=none -o IdentitiesOnly=yes -i "$ID" \
      -o ServerAliveInterval=0 -o TCPKeepAlive=no \
      "${USER}@${ahip}" 'sleep 75; echo SURVIVED' 2>&1)
rc=$?
{ printf '%s' "$out" | grep -q SURVIVED && [ $rc -eq 0 ]; } || \
  fail "75s idle (keepalive OFF) to $ahip did NOT survive (rc=$rc) -- stateful idle-drop on this path"

echo "REGRESS PASS: vulcan -> $ahip same-segment ($myprefix.0/24), direct route, ConnectTimeout=$ct, 75s idle survived."
```

---

## 10. Optional — vulcan-side hardening (`/etc/nixos/modules/core/networking.nix`)

Independent of the SSH fix; reduces latent risk on whichever path is used.

```nix
# (1) Lock rp_filter loose so an asymmetric return is never HARD-dropped
#     (a strict flip would silently drop 100% of .3.x asymmetric returns):
boot.kernel.sysctl = {
  "net.ipv4.conf.all.rp_filter"      = 2;
  "net.ipv4.conf.default.rp_filter"  = 2;
  "net.ipv4.conf.end0.rp_filter"     = 2;
  "net.ipv4.conf.wlp1s0f0.rp_filter" = 2;
};
networking.firewall.checkReversePath = false;   # the commented-out safety net

# (2) Delete the no-op asymmetric-routing service (it reports active while doing
#     nothing; the same-segment SSH fix removes the need for it). If kept, give it
#     ONE owner and remove the `|| true` masks so failures surface.

# (3) Disable WiFi powersave on the return-path NIC (helps even if .1.2 is kept):
networking.networkmanager.wifi.powersave = false;
boot.extraModprobeConfig = ''
  options brcmfmac power_save=0
'';
```

> Requires a `nixos-rebuild switch` **on vulcan** (`/etc/nixos`), pushed/applied there — not part of the clio `u switch`.

---

## 11. Open decisions for review

1. **Apply the dynamic `Match exec` fix to `config/ssh.nix`?** (Recommended — supersedes any static per-host IP given roaming.) Apply the same treatment to the `gitea` alias (`192.168.1.2:2222`)?
2. **Remote-access path:** is there a Tailscale/WireGuard route to vulcan that should get its own `Match` block for the off-LAN case?
3. **Vulcan-side hardening** (§10): apply now, or treat as follow-up? (At minimum, pinning `rp_filter=2` prevents a future strict-flip from turning intermittent timeouts into total failure.)
4. **DNS reconciliation:** unify the split-brain naming (e.g. `vulcan-wired`/`vulcan-wifi` with consistent forward+reverse and static DHCP leases) so build/service traffic and SSH agree on a path?
5. **Long-term:** any appetite for putting clio + a vulcan interface on a single shared (wired) segment, so "stable medium" and "same segment" coincide?

---

## Appendix — key evidence (verbatim)

```
# clio
en0: 192.168.3.9 ; gateway 192.168.3.1 ; MTU 1500 ; OpenSSH_10.3p1
ssh -G vulcan: hostname 192.168.1.2 ; connecttimeout none ;
               serveraliveinterval 30 ; tcpkeepalive yes ; controlpersist 1800
route get 192.168.1.2  -> gateway 192.168.3.1, dev en0   (routed; no ARP entry)
route get 192.168.3.16 -> direct, dev en0                (ARP 9c:76:0e:33:bd:90)

# both addresses are ONE host
ssh-keyscan 192.168.1.2  -> SHA256:eOmtKS8ImWRkNmCQsKKJRpMBtqVfTUah5sZiAd+pFos
ssh-keyscan 192.168.3.16 -> SHA256:eOmtKS8ImWRkNmCQsKKJRpMBtqVfTUah5sZiAd+pFos
reverse: 192.168.1.2 -> vulcan ; 192.168.3.16 -> vulcan-wifi
forward: vulcan / vulcan.lan -> 192.168.3.16

# vulcan
ip route get 192.168.3.9 [from 192.168.1.2] -> dev wlp1s0f0  (return ALWAYS via WiFi)
rp_filter = 2 (loose) on all/default/end0/wlp1s0f0
nf_conntrack: ~1.5k / 262144 ; tcp established timeout = 432000s ; NO SNAT
ip rule show -> only 0 / 32766 / 32767  (priority 50/51 asymmetric-routing rules ABSENT)
wlp1s0f0 power/control = on ; brcmfmac ; 10+ days, 0 deauth/brcmfmac events

# controlled experiment (7 trials across 3 verifiers)
75s idle, keepalive OFF -> .1.2 DROPS (rc=255), .3.16 SURVIVES (rc=0)
idle threshold on .1.2: 40/45/60s survive, 65-75s drop  (~60s gateway conntrack idle)
75s idle WITH ServerAliveInterval=30 -> .1.2 SURVIVES   (prior fix works for idle-established only)
MTU: 1472B+DF passes / 1500B fails on BOTH (no blackhole)
live transient (scouting): kex_exchange_identification: reset by peer ; Connection closed by 192.168.1.2
```

*Generated from a multi-agent diagnostic workflow (10 agents; evidence → synthesis → 3 adversarial verifiers → fix design). Primary root cause: 0/3 refuted.*
