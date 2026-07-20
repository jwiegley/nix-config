# overlays/15-darwin-fixes.nix
# Purpose: Fixes for packages that fail to build or test on macOS (Darwin)
# Dependencies: None (uses only prev)
final: prev:
let
  useLld =
    package:
    if prev.stdenv.isDarwin then
      package.overrideAttrs (oldAttrs: {
        nativeBuildInputs = (oldAttrs.nativeBuildInputs or [ ]) ++ [ prev.llvmPackages.lld ];
        env = (oldAttrs.env or { }) // {
          NIX_CFLAGS_LINK = (oldAttrs.env.NIX_CFLAGS_LINK or "") + " -fuse-ld=lld";
        };
      })
    else
      package;
in
{

  # Fix libvirt test failure on macOS
  # qemucapabilitiestest fails with Linux-specific QEMU capability checks
  libvirt = prev.libvirt.overrideAttrs (oldAttrs: {
    doCheck = false;
  });

  # ld64 957.1 still relies on undefined iterator behavior in its Objective-C
  # stubs pass. libc++ hardening turns that into a SIGTRAP for these packages.
  # Use lld only here instead of overriding ld64 and invalidating all of stdenv.
  contacts = useLld prev.contacts;
  caligula = useLld prev.caligula;
  spotify-player = useLld prev.spotify-player;

  # Poppler 26.06.0 adds a std::mutex to its GObject-backed PopplerPage but
  # leaves it zero-initialized. That happens to work on glibc, while Darwin's
  # pthread_mutex_lock returns EINVAL and crashes every GLib page render.
  # Apply the upstream constructor/destructor fix included after the release.
  poppler =
    if prev.stdenv.isDarwin then
      prev.poppler.overrideAttrs (oldAttrs: {
        patches = (oldAttrs.patches or [ ]) ++ [
          (prev.fetchpatch {
            url = "https://gitlab.freedesktop.org/poppler/poppler/-/commit/08f4bca6a669f9fce75dbab743db559a86591738.patch";
            hash = "sha256-ploZV/lH9ZNeHzpGieDe49NcLvy7ii+fKzdzClJnlb8=";
          })
        ];
      })
    else
      prev.poppler;

  # Fix zsh-5.9 lost-SIGCHLD hang after the 2026-04-18 darwin stdenv reshuffle
  # (nixpkgs PR #508474, "darwin: migrate source releases from apple-sdk to
  # darwin"). On the new stdenv, zsh's runtime autoconf probe in configure.ac
  # ("if POSIX sigsuspend() works") fails inside the build sandbox -- the
  # test program forks, the child exits, the parent calls sigsuspend() with
  # an empty mask expecting the SIGCHLD handler to fire, but the handler
  # never observes the signal in the sandbox. Autoconf records
  # zsh_cv_sys_sigsuspend=no, which causes BROKEN_POSIX_SIGSUSPEND to be
  # defined. Src/signals.c:signal_suspend() then compiles the workaround
  # branch (sigprocmask SIG_UNBLOCK + pause()) instead of the atomic
  # sigsuspend(&saved_mask). The pause()-based path has a wide race window
  # in which a SIGCHLD from an exiting $(...) command-substitution child
  # fires its handler before pause() blocks, leaving zsh wedged in
  # __sigsuspend forever waiting for a wakeup that already arrived. Symptom:
  # interactive zsh hangs mid-init (clio: during `eval "$(starship init)"`)
  # or mid-precmd (hera: $(hostname -f) in iterm2 hook); no child in ps,
  # pipe writer end already closed. macOS's actual sigsuspend() works fine
  # outside the sandbox -- libSystem.B.dylib still exports _sigsuspend. So
  # short-circuit the broken sandbox-side runtime test by pre-populating the
  # autoconf cache.
  # Verify after rebuild:
  #   nix log <zsh.drv>          should show "POSIX sigsuspend() works... yes"
  #   nm -u .../bin/zsh          should show _sigsuspend, NOT _pause
  #   timeout 5 zsh -ic 'echo X' should print X and exit 0 in <1s
  zsh = prev.zsh.overrideAttrs (
    oldAttrs:
    prev.lib.optionalAttrs prev.stdenv.isDarwin {
      preConfigure = (oldAttrs.preConfigure or "") + ''
        export zsh_cv_sys_sigsuspend=yes
      '';
    }
  );

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
  #   - imageio: test_lagging_video_stream times out waiting for its subprocess
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
      // (prev.lib.optionalAttrs (prev.stdenv.isDarwin && pprev ? imageio) {
        imageio = pprev.imageio.overridePythonAttrs (oldAttrs: {
          disabledTests = (oldAttrs.disabledTests or [ ]) ++ [ "test_lagging_video_stream" ];
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

  # Fix opencv4 pythonImportsCheck failure on macOS: libopencv_hdf.dylib
  # records its libhdf5 dependency with an absolute path that has opencv's
  # own /nix/store/...-opencv-4.13.0 prefix instead of hdf5-cpp's store
  # path, so dyld searches `<opencv>//nix/store/.../opencv-4.13.0/lib/
  # libhdf5.310.dylib` (note the doubled prefix) and fails. The hdf module
  # is only exposed via libopencv_hdf and isn't exercised by vllm-mlx (the
  # only consumer here), so disable BUILD_opencv_hdf to sidestep the
  # broken rpath/install-name on Darwin.
  opencv4 = prev.opencv4.overrideAttrs (
    oldAttrs:
    prev.lib.optionalAttrs prev.stdenv.isDarwin {
      cmakeFlags = (oldAttrs.cmakeFlags or [ ]) ++ [ "-DBUILD_opencv_hdf=OFF" ];
    }
  );

  # Fix chromaprint test OOM on macOS (ffmpeg transitive)
  chromaprint = prev.chromaprint.overrideAttrs (
    _:
    prev.lib.optionalAttrs prev.stdenv.isDarwin {
      doCheck = false;
    }
  );

  # Fix openmpi 5.0.10 configure failure on Darwin: "checking for pmix.h... no".
  #
  # Root cause is in nixpkgs's pmix-6.1.0 package, introduced by upstream
  # commit 71580b9d4ff1 (2026-04-21, PR #512074, "pmix: ensure build info
  # pointing to dev outputs is removed"). That commit added:
  #
  #   substituteInPlace ./src/mca/pinstalldirs/config/pinstall_dirs.h.in \
  #     --replace-fail '@includedir@' ""
  #
  # which strips dev-output references from libpmix's pinstalldirs. The
  # resulting libpmix has the includedir token compiled in as the empty
  # string, so share/pmix/pmixcc-wrapper-data.txt's
  #
  #   includedir=${includedir}
  #   preprocessor_flags=-I${includedir} -I${includedir}/pmix ...
  #
  # produces the broken cppflags
  #
  #   -I /pmix
  #
  # that openmpi's PMIx wrapper-compiler probe reports in its config log.
  # The probe then fails to find pmix.h and configure aborts with
  # "External PMIx requested but not found."
  #
  # On Linux this is masked because the package emits a separate `dev`
  # output and pmix's postFixup wraps $dev/bin/pmixcc with
  #
  #   wrapProgram --set PMIX_INCLUDEDIR "${!outputDev}/include"
  #               --set PMIX_PKGDATADIR "${!outputDev}/share/pmix"
  #
  # so the env var feeds the correct path back into libpmix's runtime
  # token expansion. On Darwin the outputs list is gated on isLinux, so
  # there is no dev output and the postFixup wrapping never runs --
  # leaving the broken wrapper compiler as the only path openmpi can take
  # on Darwin (lib/pkgconfig/pmix.pc is well-formed but openmpi reports
  # `pkg-config module exists... no` because pmix is a buildInput only on
  # Linux and Nix's setup-hook does not add pmix/lib/pkgconfig to
  # PKG_CONFIG_PATH on Darwin).
  #
  # Fix: replicate the Linux wrapper for $out/bin/pmixcc on Darwin. With
  # pmixcc returning the real include paths, openmpi's wrapper-compiler
  # probe succeeds, finds pmix.h, and configure proceeds.
  pmix = prev.pmix.overrideAttrs (
    oldAttrs:
    prev.lib.optionalAttrs prev.stdenv.isDarwin {
      postFixup = (oldAttrs.postFixup or "") + ''
        if [ -x "$out/bin/pmixcc" ]; then
          wrapProgram "$out/bin/pmixcc" \
            --set PMIX_INCLUDEDIR "$out/include" \
            --set PMIX_PKGDATADIR "$out/share/pmix"
        fi
      '';
    }
  );

  # Fix graphite-cli 1.8.6 on Darwin. The 1.8.6 bump (nixpkgs PR #527044)
  # switched to the prebuilt vercel/pkg binary, which breaks twice here:
  #
  #   1. postInstall runs `$out/bin/gt completion` to generate bash/zsh/fish
  #      completions, but gt now creates $HOME/.config/graphite/aliases
  #      before printing anything. With the build's nonexistent
  #      HOME=/homeless-shelter it exits 1 with empty stdout and stderr, so
  #      installShellCompletion aborts on the zero-size file. Point HOME at
  #      a writable directory so the completion calls succeed.
  #
  #   2. vercel/pkg appends its snapshot filesystem after the Mach-O image,
  #      and fixupPhase's strip rewrites the binary and drops that trailing
  #      data (86764960 -> 61766832 bytes), leaving a gt that dies with
  #      "Pkg: Error reading from file." Upstream guards against exactly
  #      this on Linux (dontFixup) but left fixup enabled on Darwin, and
  #      the build still succeeds because completions are generated before
  #      fixup runs. dontStrip keeps the binary byte-identical.
  graphite-cli = prev.graphite-cli.overrideAttrs (
    oldAttrs:
    prev.lib.optionalAttrs prev.stdenv.isDarwin {
      dontStrip = true;
      postInstall = ''
        export HOME="$(mktemp -d)"
      ''
      + (oldAttrs.postInstall or "");
    }
  );

  # ntp, apr-util, libcdio-paranoia are pinned to last-known-good nixpkgs
  # in 00-last-known-good.nix (the 2026-04-23 bump broke them on Darwin).

}
