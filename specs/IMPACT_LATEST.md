## Target

`config/darwin.nix`: `homebrew.onActivation.extraFlags = [ "--force" ]`.

The proposed change removes generic Homebrew Bundle force-install behavior while retaining nix-darwin's generated `--force-cleanup` for non-interactive cleanup.

## Dependents (2)

- `flake.nix`: `darwinConfigurations.hera` imports `config/darwin.nix`.
- `flake.nix`: `darwinConfigurations.clio` imports `config/darwin.nix`.

All Homebrew formulae and casks on both hosts pass through this activation path.

## Affected Stories

- No root `specs/release-plan.yaml` or epic capsule owns this configuration.

## Test Coverage

- No dedicated test exercises the generated Homebrew activation command.
- Verification gate: build/evaluate both Darwin systems and inspect each generated `activate` script.
- Runtime gate: switch Hera and confirm Discord stays on one PID with no ShipIt request or reinstall.
- Gap: Clio is currently unreachable, so its installed Homebrew runtime version cannot be checked live.

## Risk: High

This is a shared activation interface with no dedicated test and a runtime dependency on Homebrew CLI compatibility. Generic `--force` is demonstrably unsafe because Homebrew passes it to the installer; `--force-cleanup` scopes force to cleanup.

## Recommended action

Proceed with removal of generic `--force`, verify both generated Darwin closures, and activate on Hera. Do not claim Clio runtime validation while that host is unreachable.
