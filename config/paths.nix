# config/paths.nix
# Purpose: Centralized path definitions for external source dependencies
# These paths are derived from flake inputs for pure evaluation.
# Returns null for any input not present in the calling flake, so overlays
# can guard attributes with: lib.optionalAttrs (paths.foo != null) { ... }
#
# Usage in overlays:
#   let paths = import ../config/paths.nix { inputs = prev.inputs; }; in
#   { src = paths.scripts; }

{ inputs }:

{
  # Personal scripts collection (used by 30-user-scripts.nix)
  scripts = inputs.scripts or null;

  # Git scripts collection (used by 30-git-tools.nix)
  git-scripts = inputs.git-scripts or null;

  # Org-mode to timeclock converter (used by 30-text-tools.nix)
  org2tc = inputs.org2tc or null;

  # Hours/time tracking project (used by 10-emacs.nix)
  hours = inputs.hours or null;

  # Ledger CLI accounting flake (used by 30-ledger.nix)
  ledger = inputs.ledger or null;

  # Emacs source tree (used by 10-emacs.nix for emacsHEAD)
  emacs-src = inputs.emacs-src or null;
}
