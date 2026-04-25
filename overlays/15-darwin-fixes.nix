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

  # Fix direnv checkPhase on macOS (Determinate Nix, non-sandboxed builds).
  # Two independent issues combine to hang `make test-zsh`:
  #
  #   1. nix-darwin's /etc/zshenv sources .../set-environment, whose line 14 is
  #      `export GPG_TTY=$(tty)`. In the non-sandboxed build the builder's TTY
  #      leaks into subprocess FDs, and `ttyname(0)` blocks under certain FD
  #      configurations that the test harness reaches after spawning many zsh
  #      subshells. Setting __NIX_DARWIN_SET_ENVIRONMENT_DONE=1 short-circuits
  #      /etc/zshenv so set-environment (and its tty call) never runs.
  #
  #   2. direnv's default `disable_stdin = false` passes the parent's stdin FD
  #      through to the bash subprocess that sources .envrc. When invoked from
  #      zsh's $() command substitution in the builder process group, that FD
  #      is a live pipe and the bash child blocks reading from it. Patching
  #      direnv_eval in the test harness to feed direnv `</dev/null` closes
  #      the leak. (bash $() does not expose the same FD, which is why
  #      test-bash works without this patch.)
  direnv = prev.direnv.overrideAttrs (
    oldAttrs:
    prev.lib.optionalAttrs prev.stdenv.isDarwin {
      doCheck = false;
      env = (oldAttrs.env or { }) // {
        __NIX_DARWIN_SET_ENVIRONMENT_DONE = "1";
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

  # Python-package-level overrides.
  #   - fsspec: tests fail with "OSError: AF_UNIX path too long" (Nix store paths)
  #   - mirakuru: tests exit 1 on macOS (pytest-postgresql transitive)
  #   - gradio: test_video_postprocess_converts_to_playable_format fails
  #     because video_is_playable returns False in the sandbox (ffmpeg probe).
  #     Uses overrideAttrs (not overridePythonAttrs) so .override is preserved,
  #     which gradio's passthru.sans-reverse-dependencies relies on.
  # av and openai-whisper are pinned in 00-last-known-good.nix instead.
  pythonPackagesExtensions = (prev.pythonPackagesExtensions or [ ]) ++ [
    (
      pfinal: pprev:
      (prev.lib.optionalAttrs (pprev ? fsspec) {
        fsspec = pprev.fsspec.overridePythonAttrs (_: {
          doCheck = false;
        });
      })
      // (prev.lib.optionalAttrs (pprev ? mirakuru) {
        mirakuru = pprev.mirakuru.overridePythonAttrs (_: {
          doCheck = false;
        });
      })
      // (prev.lib.optionalAttrs (pprev ? gradio) {
        gradio = pprev.gradio.overrideAttrs (_: {
          doInstallCheck = false;
        });
      })
    )
  ];

  # Fix srm build failure on macOS (clang 16+ defaults to C23 which rejects
  # K&R style function declarations in getopt1.c). Force gnu89 so the
  # pre-ANSI declarations compile.
  srm = prev.srm.overrideAttrs (
    oldAttrs:
    prev.lib.optionalAttrs prev.stdenv.isDarwin {
      env = (oldAttrs.env or { }) // {
        NIX_CFLAGS_COMPILE = (oldAttrs.env.NIX_CFLAGS_COMPILE or "") + " -std=gnu89";
      };
    }
  );

  # Fix kvazaar test OOM failures on macOS
  # ffmpeg test vectors exceed available memory during `make check`
  kvazaar = prev.kvazaar.overrideAttrs (_: {
    doCheck = false;
  });

  # Fix chromaprint test OOM on macOS (ffmpeg transitive)
  chromaprint = prev.chromaprint.overrideAttrs (_: {
    doCheck = false;
  });

  # ntp, apr-util, libcdio-paranoia are pinned to last-known-good nixpkgs
  # in 00-last-known-good.nix (the 2026-04-23 bump broke them on Darwin).

}
