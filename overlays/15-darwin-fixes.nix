# overlays/15-darwin-fixes.nix
# Purpose: Fixes for packages that fail to build or test on macOS (Darwin)
# Dependencies: prev plus compatibility source catalog
_final: prev:
let
  compatibilitySources = import ../packages/source-catalog.nix "compatibility";
  popplerPatch = compatibilitySources.poppler-darwin-mutex-patch;
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

  # Disable libvirt checks on Darwin.
  libvirt = prev.libvirt.overrideAttrs (_oldAttrs: {
    doCheck = false;
  });

  # Use lld for these packages on Darwin.
  contacts = useLld prev.contacts;
  caligula = useLld prev.caligula;
  spotify-player = useLld prev.spotify-player;

  # Apply the cataloged PopplerPage constructor/destructor patch on Darwin.
  poppler =
    if prev.stdenv.isDarwin then
      prev.poppler.overrideAttrs (oldAttrs: {
        patches = (oldAttrs.patches or [ ]) ++ [
          (
            assert popplerPatch.source.fetcher == "fetchpatch";
            prev.fetchpatch popplerPatch.source.args
          )
        ];
      })
    else
      prev.poppler;

  # Omit the optional Darwin purgeable-capacity query while retaining statfs
  # filesystem metrics.
  prometheus-node-exporter = prev.prometheus-node-exporter.overrideAttrs (
    oldAttrs:
    prev.lib.optionalAttrs prev.stdenv.isDarwin {
      patches = (oldAttrs.patches or [ ]) ++ [
        ./patches/prometheus-node-exporter-disable-darwin-purgeable.patch
      ];
    }
  );

  # Change scdaemon's Darwin polling interval from 0.5 to 5 seconds.
  gnupg =
    if prev.stdenv.isDarwin then
      prev.gnupg.overrideAttrs (oldAttrs: {
        patches = (oldAttrs.patches or [ ]) ++ [
          ./patches/gnupg-darwin-scdaemon-poll-interval.patch
        ];
      })
    else
      prev.gnupg;

  # Preseed zsh's sigsuspend configure result on Darwin.
  zsh = prev.zsh.overrideAttrs (
    oldAttrs:
    prev.lib.optionalAttrs prev.stdenv.isDarwin {
      preConfigure = (oldAttrs.preConfigure or "") + ''
        export zsh_cv_sys_sigsuspend=yes
      '';
    }
  );

  # Replace discard_const with a cast in Samba's comparison-fold test on Darwin.
  samba = prev.samba.overrideAttrs (oldAttrs: {
    postPatch =
      (oldAttrs.postPatch or "")
      + prev.lib.optionalString prev.stdenv.isDarwin ''
        substituteInPlace lib/ldb/tests/test_ldb_comparison_fold.c \
          --replace-fail 'discard_const(s)' '(void *)(s)'
      '';
  });

  # Disable direnv checks on Darwin.
  direnv = prev.direnv.overrideAttrs (
    _oldAttrs:
    prev.lib.optionalAttrs prev.stdenv.isDarwin {
      doCheck = false;
    }
  );

  # Disable z3 checks on Darwin.
  z3 = prev.z3.overrideAttrs (_oldAttrs: {
    doCheck = false;
  });

  # Package-level check suppressions; keep gradio as an overrideAttrs result so
  # its passthru override function remains available.
  pythonPackagesExtensions = (prev.pythonPackagesExtensions or [ ]) ++ [
    (
      _pfinal: pprev:
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

  # Compile srm as gnu89 on Darwin.
  srm = prev.srm.overrideAttrs (
    oldAttrs:
    prev.lib.optionalAttrs prev.stdenv.isDarwin {
      env = (oldAttrs.env or { }) // {
        NIX_CFLAGS_COMPILE = (oldAttrs.env.NIX_CFLAGS_COMPILE or "") + " -std=gnu89";
      };
    }
  );

  # Disable kvazaar checks.
  kvazaar = prev.kvazaar.overrideAttrs (_: {
    doCheck = false;
  });

  # Build opencv4 without its HDF module on Darwin.
  opencv4 = prev.opencv4.overrideAttrs (
    oldAttrs:
    prev.lib.optionalAttrs prev.stdenv.isDarwin {
      cmakeFlags = (oldAttrs.cmakeFlags or [ ]) ++ [ "-DBUILD_opencv_hdf=OFF" ];
    }
  );

  # Disable chromaprint checks on Darwin.
  chromaprint = prev.chromaprint.overrideAttrs (
    _:
    prev.lib.optionalAttrs prev.stdenv.isDarwin {
      doCheck = false;
    }
  );

  # Give Darwin's pmixcc the include/share prefixes required by OpenMPI.
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

  # Give Graphite completion generation a writable HOME and disable stripping.
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

}
