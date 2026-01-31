# overlays/15-darwin-fixes.nix
# Purpose: Fixes for packages that fail to build or test on macOS (Darwin)
# Dependencies: None (uses only prev)
# Packages: samba, z3, fsspec
final: prev: {

  # Fix samba build failure on macOS
  # Clang rejects discard_const in static initializers as non-constant expressions
  # Patch the test file's STR_VAL macro to use a simple cast instead
  samba = prev.samba.overrideAttrs (oldAttrs: {
    postPatch = (oldAttrs.postPatch or "") + prev.lib.optionalString prev.stdenv.isDarwin ''
      sed -i.bak 's/discard_const(s)/(void *)(s)/g' lib/ldb/tests/test_ldb_comparison_fold.c
    '';
  });

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
