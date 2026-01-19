# config/paths.nix
# Purpose: Centralized path definitions for external source dependencies
# These paths point to local source checkouts used by overlays
#
# Usage in overlays:
#   let paths = import ../config/paths.nix; in
#   { src = paths.scripts; }
#
# Note: All paths must exist on the machine for the build to succeed.
# If a path doesn't exist, the corresponding overlay package won't build.

{
  # Base directory for all source checkouts
  srcBase = /Users/johnw/src;

  # Personal scripts collection (used by 30-user-scripts.nix)
  scripts = /Users/johnw/src/scripts;

  # Git scripts collection (used by 30-git-tools.nix)
  gitScripts = /Users/johnw/src/git-scripts;

  # Directory scanning utility (used by 30-data-tools.nix)
  dirscan = /Users/johnw/src/dirscan;

  # Org-mode to timeclock converter (used by 30-text-tools.nix)
  org2tc = /Users/johnw/src/hours/org2tc;

  # Hours/time tracking project (used by 10-emacs.nix)
  hours = /Users/johnw/src/hours;

  # Ledger CLI accounting (used by 30-ledger.nix)
  ledger = /Users/johnw/src/ledger;

  # Optional/commented paths (for reference)
  # proofGeneral = /Users/johnw/src/proof-general;
  # coq = /Users/johnw/src/coq;
}
