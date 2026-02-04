# config/paths.nix
# Purpose: Centralized path definitions for external source dependencies
# These paths are derived from flake inputs for pure evaluation.
#
# Usage in overlays:
#   let paths = import ../config/paths.nix { inputs = prev.inputs; }; in
#   { src = paths.scripts; }

{ inputs }:

{
  # Personal scripts collection (used by 30-user-scripts.nix)
  scripts = inputs.scripts;

  # Git scripts collection (used by 30-git-tools.nix)
  gitScripts = inputs.git-scripts;

  # Directory scanning utility (used by 30-data-tools.nix)
  dirscan = inputs.dirscan;

  # Org-mode to timeclock converter (used by 30-text-tools.nix)
  org2tc = inputs.org2tc;

  # Hours/time tracking project (used by 10-emacs.nix)
  hours = inputs.hours;

  # Ledger CLI accounting flake (used by 30-ledger.nix)
  ledger = inputs.ledger;

  # Emacs source tree (used by 10-emacs.nix for emacsHEAD)
  emacsSrc = inputs.emacs-src;
}
