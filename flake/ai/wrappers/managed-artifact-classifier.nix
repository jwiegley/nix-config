# Shell helper shared by every client wrapper.
#
# Classifies a set of Nix-managed artifacts as `zero`, `complete`, or
# `partial`, which is what each wrapper uses to decide whether generating
# over the set is safe. The `-L` arm is load-bearing: `-e` follows symlinks
# and reports false for a dangling one, so without it a dangling symlink
# would classify as `zero` and be silently replaced.
#
# This lives in one file because `6094451a` split the wrappers out of
# flake/ai.nix and left three byte-identical copies behind. A correction to
# the symlink handling applied to whichever copy the reader happened to open
# would leave the other two clients on the old behaviour, and the divergence
# would be invisible -- nothing fails, and the stale copies keep working for
# every case except the one the fix addressed.
''
  classify_managed_artifacts() {
    local artifact
    local all_absent=1
    local all_regular=1

    [ "$#" -gt 0 ] || return 2
    for artifact in "$@"; do
      if [ -e "$artifact" ] || [ -L "$artifact" ]; then
        all_absent=0
      fi
      if [ ! -f "$artifact" ]; then
        all_regular=0
      fi
    done

    if [ "$all_absent" -eq 1 ]; then
      printf '%s\n' zero
    elif [ "$all_regular" -eq 1 ]; then
      printf '%s\n' complete
    else
      printf '%s\n' partial
    fi
  }
''
