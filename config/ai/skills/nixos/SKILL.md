---
name: nixos
description: Resolve NixOS issues using research and sequential thinking. Use when
  diagnosing or fixing problems on a NixOS host -- failed builds or switches, broken
  services or modules, configuration errors -- or whenever the user mentions NixOS,
  nixos-rebuild, or /etc/nixos.
---
Use nix-pro and the available NixOS tooling to resolve issues with the current
NixOS installation.

- Do not, under any circumstances, decrypt the SOPS secrets.yaml file. See the
  @CLAUDE.md file for extensive notes on this important security consideration.

- Use available live web search as needed for research and discovering resources.

- Use sequential-thinking when appropriate to break down tasks further.

- On a managed NixOS host, run builds and switches through the host's build
  driver from `/etc/nixos`, for example `cd /etc/nixos && ./build switch`.
  For a custom command use `./build -- COMMAND ...`. The driver owns the
  `.nixos-build` lock; never create, remove, or seize that path manually. If
  the driver cannot acquire its lock, report its error and stop.

- VPS is parked and must be selected explicitly for maintenance. On VPS, pass
  `--max-jobs 1 --cores 1` to every `./build build` and `./build switch`
  invocation.
