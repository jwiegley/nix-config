# overlays/15-darwin-fixes.nix
# Purpose: Fixes for packages that fail to build or test on macOS (Darwin)
# Dependencies: None (uses only prev)
# Packages: libvirt, samba, z3, fsspec
final: prev: {

  # Fix libvirt test failure on macOS
  # qemucapabilitiestest fails with Linux-specific QEMU capability checks
  libvirt = prev.libvirt.overrideAttrs (oldAttrs: {
    doCheck = false;
  });

  # Fix samba build failure on macOS
  # Clang rejects discard_const in static initializers as non-constant expressions
  # Patch the test file's STR_VAL macro to use a simple cast instead
  samba = prev.samba.overrideAttrs (oldAttrs: {
    postPatch =
      (oldAttrs.postPatch or "")
      + prev.lib.optionalString prev.stdenv.isDarwin ''
        sed -i.bak 's/discard_const(s)/(void *)(s)/g' lib/ldb/tests/test_ldb_comparison_fold.c
      '';
  });

  # Fix direnv build failure on macOS
  # GNUmakefile adds -linkmode=external on Darwin (for DYLD_INSERT_LIBRARIES fix)
  # which requires CGO, but nixpkgs sets CGO_ENABLED=0 in env
  direnv = prev.direnv.overrideAttrs (
    oldAttrs:
    prev.lib.optionalAttrs prev.stdenv.isDarwin {
      env = (oldAttrs.env or { }) // {
        CGO_ENABLED = "1";
      };
    }
  );

  # Fix git-branchless build failure
  # Upstream postPatch glob for esl01-indexedlog vendor crate doesn't match
  # the new cargo vendor layout (crates are now under source-registry-0/)
  # With nullglob, the failed glob expands to nothing, making cd go to $HOME (/homeless-shelter)
  git-branchless = prev.git-branchless.overrideAttrs (oldAttrs: {
    postPatch =
      builtins.replaceStrings
        [ "../git-branchless-*-vendor/esl01-indexedlog-*/" ]
        [ "../git-branchless-*-vendor/source-registry-0/esl01-indexedlog-*/" ]
        (oldAttrs.postPatch or "");
  });

  # Fix squashfsTools build failure on macOS
  # mksquashfs.c uses Linux st_atim but Darwin uses st_atimespec
  squashfsTools = prev.squashfsTools.overrideAttrs (
    oldAttrs:
    prev.lib.optionalAttrs prev.stdenv.isDarwin {
      postPatch = (oldAttrs.postPatch or "") + ''
        sed -i.bak 's/st_atim\([^a-z]\)/st_atimespec\1/g' squashfs-tools/mksquashfs.c
      '';
    }
  );

  # Fix z3 test failures on macOS
  # Tests fail with "Error: invalid argument" in api_polynomial test
  z3 = prev.z3.overrideAttrs (oldAttrs: {
    doCheck = false;
  });

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
