# Security Review Report

**Repository:** jwiegley/nix-config  
**Date:** 2026-04-09  
**Scope:** Full repository — flake inputs, overlays, secrets/credential handling, SSH/key management, package pinning/supply chain, network/service security, insecure fetchers, and sandbox escapes  
**Hosts reviewed:** hera, clio (Darwin), vulcan (NixOS), vps (NixOS), andoria (Ubuntu/home-manager)

---

## Executive Summary

15 findings across 4 severity levels. Three are critical: a build sandbox escape, a hardcoded network service password, and exposure of the Nix signing key path. Four are high-severity, involving credential leakage in process listings, disabled TLS verification, unauthenticated metrics exposure, and broad SSH agent forwarding. The remaining findings are medium or low risk but still warrant attention.

---

## Findings

### CRITICAL

#### 1. Build sandbox escape via `__noChroot = true`

- **File:** `overlays/30-mapq.nix:22`
- **Risk:** The `__noChroot = true` attribute completely disables the Nix build sandbox for the `mapq` package. During the build, the process has unrestricted filesystem access — it can read `~/.gnupg`, `~/.ssh`, password stores, and any other user data. A compromised or malicious build script could exfiltrate secrets, modify the build output based on local state, or plant backdoors that are invisible to later review.
- **Context:** This exists because mapq requires Xcode's Swift compiler and MapKit framework, which live outside the Nix store. The `dontFixup = true` on line 25 further means no post-build validation occurs.
- **Remediation:**
  1. **Preferred:** Build mapq outside of Nix (e.g., as a standalone Makefile or script that installs to a known prefix) and wrap the resulting binary with `wrapProgram` in a trivial Nix derivation. This keeps the unsafe build completely separate from Nix's overlay system.
  2. **If kept in Nix:** Add `requiredSystemChecks` or use `__structuredAttrs` with strict sandbox allowlists. At minimum, add a comment documenting the exact paths the build needs and audit the build script regularly.
  3. Verify the built binary with `codesign` verification after each build.

#### 2. Hardcoded VLC telnet password

- **File:** `config/darwin.nix:750`
- **Risk:** VLC is started with `--telnet-password=secret` on port 4212. The password `secret` is trivially guessable and committed in plaintext to the repository. Any device on the LAN can connect to port 4212, authenticate with `secret`, and issue VLC commands (play arbitrary media, execute VLC lua scripts, etc.).
- **Remediation:**
  1. Read the password from a file or password-store entry, similar to the MSSQL pattern already used elsewhere in the same file: `VLC_TELNET_PASSWORD=$(pass vlc/telnet)`.
  2. Bind VLC to `127.0.0.1` instead of all interfaces: add `--telnet-host=127.0.0.1` to the VLC command.
  3. Consider whether telnet control of VLC is needed at all — if it's only for automation, a local unix socket or D-Bus interface would be safer.

#### 3. Nix signing key path exposed in configuration

- **File:** `config/darwin.nix:409`
- **Risk:** The line `secret-key-files = ${xdg_configHome}/gnupg/nix-signing-key.sec` references the private Nix signing key. If this key is compromised, an attacker can sign arbitrary NARs, allowing them to inject malicious substitutes that will be trusted by any host configured to trust this key. The path itself being committed to the repo tells an attacker exactly where to look.
- **Remediation:**
  1. Move the signing key configuration behind an optional flag or conditional so it's only loaded when actually needed for signing operations.
  2. Consider using a separate signing-only key that is stored on removable media or in a hardware token, loaded only during `nix sign` operations.
  3. At minimum, ensure the signing key file has restrictive permissions (`chmod 600`) and is not in any directory accessible via the mapq sandbox escape (finding 1).

---

### HIGH

#### 4. MSSQL SA password visible in process listing

- **File:** `config/darwin.nix:565-586`
- **Risk:** The SA password is read from a file (`~/.config/mssql/passwd`) and passed as an environment variable to Docker via `-e "MSSQL_SA_PASSWORD=$MSSQL_SA_PASSWORD"`. Environment variables of running processes are visible to any user via `ps eww` or `/proc/PID/environ` on Linux. While macOS has some restrictions on process visibility, any user on the host can still see these variables.
- **Remediation:**
  1. Use Docker's `--secret` or `--env-file` with a protected file instead of `-e`:
     ```
     docker run --env-file <(echo "MSSQL_SA_PASSWORD=$(cat ~/.config/mssql/passwd)") ...
     ```
     Note: `--env-file` still exposes via `ps` on some platforms.
  2. **Better:** Use Docker secrets (Swarm mode) or mount the password file into the container and have MSSQL read it directly.
  3. **Best:** Use `docker run --secret mssql-password` with a Docker secret, which keeps the password out of the environment entirely.

#### 5. nginx reverse proxy has SSL verification disabled

- **File:** `config/darwin.nix:678`
- **Risk:** `proxy_ssl_verify off;` disables TLS certificate verification for the upstream connection to `chat.vulcan.lan`. This allows man-in-the-middle attacks between the nginx proxy and the upstream server — an attacker on the network can intercept, read, and modify all traffic to the chat service.
- **Remediation:**
  1. Generate a self-signed CA or use a proper internal CA (e.g., step-ca, smallstep) for `chat.vulcan.lan`.
  2. Configure `proxy_ssl_certificate` and `proxy_ssl_trusted_certificate` pointing to the CA cert.
  3. Remove `proxy_ssl_verify off;` and set `proxy_ssl_verify on;` (the default).
  4. If the upstream uses a self-signed cert, add it to `proxy_ssl_trusted_certificate` instead of disabling verification entirely.

#### 6. Prometheus node exporter bound to 0.0.0.0 without authentication

- **File:** `config/darwin.nix:110`
- **Risk:** `listenAddress = "0.0.0.0"` exposes the Prometheus node exporter on port 9100 to the entire network without any authentication or encryption. Anyone on the LAN (or the internet if the host is not firewalled) can scrape detailed system metrics: CPU, memory, disk, network, process information — useful for reconnaissance.
- **Remediation:**
  1. Bind to `127.0.0.1` and configure Prometheus to scrape via localhost.
  2. If remote scraping is required, use an nginx reverse proxy with TLS and basic auth in front of the exporter.
  3. Add macOS firewall rules (`pf`) to restrict access to port 9100.

#### 7. SSH agent forwarding enabled for multiple hosts

- **File:** `config/johnw.nix:1025,1042,1052`
- **Risk:** `forwardAgent = true` is set for hera, clio, and vulcan. SSH agent forwarding allows a compromised server to use your local SSH agent to authenticate to other hosts. If any of these machines is compromised, the attacker can pivot to every other host that trusts your agent.
- **Remediation:**
  1. Remove `forwardAgent = true` from all host configurations.
  2. Use `ProxyJump` / `ProxyCommand` instead, which establishes direct SSH connections without exposing the agent to intermediate hosts.
  3. If agent forwarding is truly needed for a specific workflow, enable it only for that specific host with a comment explaining why, and use `ssh -A` ad-hoc rather than enabling it permanently in config.

---

### MEDIUM

#### 8. Pre-built binaries without source verification

- **Files:** `overlays/30-sherlock-db.nix`, `overlays/30-git-tools.nix` (git-lfs on Darwin)
- **Risk:** These overlays download pre-built binaries from GitHub releases and install them directly. While hashes are pinned (providing integrity), there is no source verification — the binary could differ from the published source code. The `sherlock-db` overlay correctly declares `sourceProvenance = [ sourceTypes.binaryNativeCode ]` but this does not mitigate the trust issue.
- **Remediation:**
  1. Prefer building from source when possible.
  2. For pre-built binaries, verify GPG signatures or checksums published alongside the release.
  3. Consider using `nix-auth` or a separate verification step.
  4. Document the trust decision in comments.

#### 9. vllm-mlx bypasses Nix purity via `uv tool install` at runtime

- **File:** `overlays/30-vllm-mlx.nix`
- **Risk:** The wrapper script runs `uv tool install vllm-mlx` on first invocation, installing Python packages from PyPI outside of Nix's control. This means:
  - The installed packages are not reproducible (PyPI serves different content over time).
  - No hash verification of the runtime-installed packages.
  - The `~/.local/share/uv/tools` directory is outside the Nix store and not garbage-collected.
  - Security updates must be applied manually by the user.
- **Remediation:**
  1. Build vllm-mlx as a proper Python derivation using `python3.pkgs.buildPythonApplication` with pinned dependencies.
  2. If Apple Metal requirements prevent sandboxed builds, use a FOD (fixed-output derivation) with `fetchurl` for the wheel, similar to how other Python packages are handled.
  3. At minimum, add a hash check for the installed tool version and warn when the installed version differs from the Nix-declared version.

#### 10. Pervasive `doCheck = false` across overlays

- **Files:** `overlays/30-ai-llm.nix`, `overlays/30-ai-mcp.nix`, `overlays/30-ai-python.nix`, `overlays/15-darwin-fixes.nix`
- **Risk:** Many overlay packages disable test suites with `doCheck = false` or `doInstallCheck = false`. This means the build succeeds even if the package is broken. While often necessary for Python packages with complex test dependencies or Darwin-specific build issues, it reduces confidence in build correctness.
- **Remediation:**
  1. Enable tests where feasible and add `doCheck = true` with appropriate `checkInputs`.
  2. For packages where tests cannot run, add a comment explaining why and reference the upstream issue.
  3. Consider running tests as a separate CI step rather than during the build.

#### 11. SMB signing disabled

- **File:** `config/darwin.nix:73`
- **Risk:** `signing_required=no` in the nsmb.conf allows SMB connections without cryptographic signatures. This makes SMB traffic vulnerable to man-in-the-middle attacks where an attacker can modify data in transit.
- **Remediation:**
  1. Change to `signing_required=yes` or remove the line (macOS defaults to requiring signing for SMB 3+).
  2. If older SMB servers require unsigned connections, restrict the exception to specific servers using per-server sections.

#### 12. Chrome remote debugging port forwarded to VPS

- **File:** `config/darwin.nix:735,757-766`
- **Risk:** Chrome is started with `--remote-debugging-port=9223` and this port is forwarded via autossh to the VPS (`-R 127.0.0.1:9222:127.0.0.1:9223`). Anyone with access to port 9222 on the VPS can connect to the Chrome DevTools Protocol, which provides full browser control: reading cookies, navigating pages, executing JavaScript, accessing local storage, etc.
- **Remediation:**
  1. Ensure port 9222 on the VPS is only accessible to localhost and not exposed to the internet.
  2. Add authentication to the Chrome debug port using `--remote-debugging-auth` or a proxy with basic auth.
  3. Consider whether this tunnel is still needed — if it's for automated browsing, consider a headless browser in a container on the VPS instead.

---

### LOW

#### 13. `.gitignore` missing sensitive file patterns

- **File:** `.gitignore`
- **Risk:** The `.gitignore` only covers `.DS_Store`, `/result*`, `/.claude`, and `__pycache__/`. It does not exclude common sensitive patterns like `*.sec`, `*.key`, `*.pem`, `*.p12`, `*.gnupg`, `*.password`, or credential files. While no secrets are currently committed, a future accident (e.g., saving a password file in the wrong directory) could easily be committed.
- **Remediation:** Add patterns for sensitive files:
  ```
  # Credentials and keys
  *.sec
  *.key
  *.pem
  *.p12
  *.pfx
  *.gnupg
  *.password
  *.passwd
  .env
  ```

#### 14. `flake = false` inputs reduce reproducibility

- **File:** `flake.nix` (referenced in CLAUDE.md architecture docs)
- **Risk:** Several flake inputs use `flake = false`, which means Nix doesn't verify their outputs structure. While the lock file still pins revisions, the lack of flake schema validation means changes to the upstream repository layout could silently break builds or introduce unexpected behavior.
- **Remediation:** This is a known trade-off for inputs that aren't proper flakes. Where possible, encourage upstream projects to provide flake metadata or wrap them in a local flake.

#### 15. LiteLLM API key placeholders in committed config

- **File:** `litellm_proxy_config.yaml:230-233`
- **Risk:** The `environment_variables` section has empty string values for all API keys. While currently empty (keys come from `os.environ/`), this pattern creates risk: if someone fills in the values and commits, the keys would be in plaintext in git history. The `os.environ/` pattern used in `model_list` is good practice, but the `environment_variables` section at the bottom is a footgun.
- **Remediation:**
  1. Remove the `environment_variables` section entirely — the `os.environ/` references in `model_list` are sufficient.
  2. Add `litellm_proxy_config.yaml` to `.gitignore` if local overrides are needed.

---

## Positive Security Practices

The following practices are already in place and demonstrate security awareness:

| Practice | Location | Notes |
|----------|----------|-------|
| `allowInsecure = false` | `config/darwin.nix` | Explicitly rejects insecure packages |
| `hashKnownHosts = true` | `config/johnw.nix` | SSH verifies host key hashes |
| `forwardAgent = false` default | `config/johnw.nix` | Safe default; only overridden for specific hosts |
| Password-store integration | `config/johnw.nix` | Credentials for rclone, restic, SMTP, git use `pass` |
| GPG commit signing | `config/johnw.nix` | Git commits signed by default |
| Per-host SSH identity files | `config/johnw.nix` | Different keys per host |
| Nix signing key configured | `config/darwin.nix` | Binary cache signing is enabled |
| Flake lock file pins inputs | `flake.lock` | All input revisions are locked |
| `verify-inputs` Makefile target | `Makefile` | Checks for NAR hash mismatches |
| `permittedInsecurePackages` empty | `config/darwin.nix` | No insecure packages whitelisted |
| `sourceProvenance` declared | `overlays/30-sherlock-db.nix` | Binary provenance is documented |
| MSSQL password via file, not hardcoded | `config/darwin.nix:560` | Better than plaintext in config |
| Chrome debug bound to localhost | `config/darwin.nix:761` | Not exposed on all interfaces |
| Autossh tunnel bound to localhost | `config/darwin.nix:732-735` | Forwardings use `127.0.0.1` |
| PostgreSQL bound to localhost | `config/darwin.nix` (commented out) | Would be localhost when enabled |

---

## Risk Summary

| Severity | Count | Findings |
|----------|-------|----------|
| Critical | 3 | Sandbox escape, hardcoded password, signing key exposure |
| High | 4 | Credential in `ps`, SSL verify off, unauthenticated exporter, SSH agent forwarding |
| Medium | 5 | Pre-built binaries, Nix purity bypass, disabled tests, SMB signing, Chrome debug tunnel |
| Low | 3 | Incomplete .gitignore, `flake = false`, API key footgun |

---

## Recommended Priority Order

1. **Immediate:** Finding 1 (`__noChroot`) — sandbox escape affects every build
2. **Immediate:** Finding 2 (VLC password) — network-accessible service with known password
3. **Short-term:** Finding 5 (nginx SSL verify) — MITM on internal services
4. **Short-term:** Finding 6 (Prometheus on 0.0.0.0) — information disclosure on LAN
5. **Short-term:** Finding 7 (SSH agent forwarding) — lateral movement risk
6. **Medium-term:** Finding 3 (signing key path) — mitigate with finding 1 first
7. **Medium-term:** Finding 4 (MSSQL password in env) — credential exposure
8. **Medium-term:** Finding 12 (Chrome debug tunnel) — browser compromise risk
9. **When convenient:** Findings 8, 9, 10, 11 — supply chain and hardening
10. **When convenient:** Findings 13, 14, 15 — defense in depth