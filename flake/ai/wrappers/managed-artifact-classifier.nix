# Shell helper shared by every client wrapper.
#
# Classifies Nix-managed artifact sets as `zero`, `complete`, or `partial` so
# wrappers can inject, pass through, or reject them consistently. `-L` keeps a
# dangling symlink from being mistaken for an absent artifact.
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
