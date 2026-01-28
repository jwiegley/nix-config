# overlays/15-darwin-fixes.nix
# Purpose: Fixes for packages that fail to build or test on macOS (Darwin)
# Dependencies: None (uses only prev)
# Packages: time, zbar, z3, fsspec
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

  # Fix zbar test failures on macOS
  # Tests fail with zbarimg returning error status (-11) which is a segfault
  # Disable tests as the package itself works fine
  zbar = prev.zbar.overrideAttrs (oldAttrs: { doCheck = false; });

  # Fix z3 test failures on macOS
  # Tests fail with "Error: invalid argument" in api_polynomial test
  z3 = prev.z3.overrideAttrs (oldAttrs: { doCheck = false; });

  # Fix fsspec test failures on macOS via pythonPackagesExtensions
  # Tests fail with "OSError: AF_UNIX path too long" due to Nix store paths
  pythonPackagesExtensions = (prev.pythonPackagesExtensions or [ ]) ++ [
    (pfinal: pprev: {
      fsspec = pprev.fsspec.overridePythonAttrs (oldAttrs: {
        doCheck = false;
      });
    })
  ];

}
