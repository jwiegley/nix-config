# Vulcan SSH Routing

`config/ssh.nix` currently gives `vulcan` a wired fallback at `192.168.1.2` and
emits an earlier conditional block that selects `192.168.3.16` when the client is
on the matching local segment. `test/home-manager-release-skew.nix` verifies the
ordering survives supported Home Manager API variants.

This prevents the known cross-subnet path on the covered Hera/Clio topology, but it
does not prove general roaming behavior:

- selection recognizes one current interface/address condition;
- `Host vulcan` has no bounded `ConnectTimeout`;
- repository tests verify rendering, not route symmetry, handshake latency, or idle
  survival; and
- Vulcan-side routing or power-management changes belong to its separate NixOS
  configuration.

For a live diagnosis, inspect the resolved destination and route before changing
configuration:

```bash
ssh -G vulcan | sed -n '/^hostname /p;/^connecttimeout /p'
route -n get "$(ssh -G vulcan | awk '$1 == "hostname" { print $2; exit }')"
```

Keep any future fix in `config/ssh.nix` and extend the rendering test. Do not retain
host snapshots, interface dumps, or long-running probe logs in repository docs.
