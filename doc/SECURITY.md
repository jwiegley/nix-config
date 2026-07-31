# Security Notes

This is a source-backed ledger of current hardening work. It is not a claim about
live exposure; verify the active generation and network boundary before changing a
disposition.

| Area | Current source | Required decision or verification |
|---|---|---|
| VLC control | `config/launchd.nix` passes a literal telnet password | Remove the service, bind it locally, or move authentication out of argv/config |
| MSSQL | `config/launchd.nix` expands the SA password into Docker's environment | Decide whether the service remains needed; otherwise adopt a file/secret boundary |
| Node exporter | `config/darwin.nix` can listen on `0.0.0.0` | Verify firewall and scrape topology; prefer a bounded interface |
| SSH agent forwarding | `config/ssh.nix` enables forwarding for several hosts | Reduce to the hosts/workflows that demonstrably require it |
| SMB signing | `config/darwin.nix` writes `signing_required=no` | Verify server compatibility, then restore signing where possible |
| Chrome debug tunnel | `config/launchd.nix` forwards the local debug port to VPS localhost | Verify VPS access boundaries and whether the tunnel is still needed |
| Native binaries and wheels | Sherlock and vllm-mlx use pinned upstream artifacts | Keep hashes and provenance explicit; prefer source builds when practical |
| Disabled package checks | Several package overrides disable upstream tests | Keep a local reason and a smaller install/import check for each exception |
| Sensitive filenames | `.gitignore` intentionally has a small allowlist | Decide whether repository-wide key/credential patterns would hide legitimate public material before broadening it |

Already resolved in current source: the former mapq sandbox escape and disabled
upstream TLS verification are absent. A configured signing-key pathname is not
itself key exposure; do not inspect or record key material while auditing custody.

Security fixes belong in focused changes with a concrete active-state check. Git
history retains the superseded point-in-time audit and its original severity model.
