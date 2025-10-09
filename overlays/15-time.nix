final: prev: {
  # Fix time package build failure on macOS
  # The source uses __sighandler_t which is not available on Darwin
  # Use sed to replace the incorrect type name during the patch phase
  time = prev.time.overrideAttrs (oldAttrs: {
    postPatch = (oldAttrs.postPatch or "") + ''
      echo "Patching src/time.c to fix __sighandler_t on macOS"
      sed -i.bak 's/__sighandler_t/sighandler_t/g' src/time.c
    '';
  });
}
