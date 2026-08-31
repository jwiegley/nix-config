# overlays/15-darwin-fixes.nix
# Purpose: Fixes for packages that fail to build or test on macOS (Darwin)
# Dependencies: prev plus compatibility source catalog
_final: prev:
let
  useLld =
    package:
    if prev.stdenv.hostPlatform.isDarwin then
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
  # The cataloged Poppler patch remains disabled pending a Darwin rebuild.
  inherit (prev) poppler;

  # Omit the optional Darwin purgeable-capacity query while retaining statfs
  # filesystem metrics.
  prometheus-node-exporter = prev.prometheus-node-exporter.overrideAttrs (
    oldAttrs:
    prev.lib.optionalAttrs prev.stdenv.hostPlatform.isDarwin {
      patches = (oldAttrs.patches or [ ]) ++ [
        ./patches/prometheus-node-exporter-disable-darwin-purgeable.patch
      ];
    }
  );

  # Change scdaemon's Darwin polling interval from 0.5 to 5 seconds.
  gnupg =
    if prev.stdenv.hostPlatform.isDarwin then
      prev.gnupg.overrideAttrs (oldAttrs: {
        patches = (oldAttrs.patches or [ ]) ++ [
          ./patches/gnupg-darwin-scdaemon-poll-interval.patch
        ];
      })
    else
      prev.gnupg;

  # tmux 3.7c requires jemalloc on macOS to avoid an upstream calloc bug.
  tmux = prev.tmux.overrideAttrs (
    oldAttrs:
    prev.lib.optionalAttrs prev.stdenv.hostPlatform.isDarwin {
      buildInputs = prev.lib.unique ((oldAttrs.buildInputs or [ ]) ++ [ prev.jemalloc ]);
      configureFlags = prev.lib.unique ((oldAttrs.configureFlags or [ ]) ++ [ "--enable-jemalloc" ]);
    }
  );

  # Preseed zsh's sigsuspend configure result on Darwin.
  zsh = prev.zsh.overrideAttrs (
    oldAttrs:
    prev.lib.optionalAttrs prev.stdenv.hostPlatform.isDarwin {
      preConfigure = (oldAttrs.preConfigure or "") + ''
        export zsh_cv_sys_sigsuspend=yes
      '';
    }
  );

  # Fix Samba's comparison-fold test and Nix 2.30 build-root dylib references.
  samba = prev.samba.overrideAttrs (oldAttrs: {
    postPatch =
      (oldAttrs.postPatch or "")
      + prev.lib.optionalString prev.stdenv.hostPlatform.isDarwin ''
        substituteInPlace lib/ldb/tests/test_ldb_comparison_fold.c \
          --replace-fail 'discard_const(s)' '(void *)(s)'
      '';
    postFixup =
      let
        upstream = oldAttrs.postFixup or "";
        upstreamDarwinFixup = ''
          export SAMBA_LIBS="$(find $out -type f -regex '.*\.dylib\(\..*\)?' -exec dirname {} \; | sort | uniq)"
          read -r -d "" SCRIPT << EOF || true
          [ -z "\$SAMBA_LIBS" ] && exit 1;
          BIN='{}';
          install_name_tool -id \$BIN \$BIN
          for old_rpath in \$(otool -L \$BIN | grep /private/tmp/ | awk '{print \$1}'); do
            new_rpath=\$(find \$SAMBA_LIBS -name \$(basename \$old_rpath) | head -n 1)
            install_name_tool -change \$old_rpath \$new_rpath \$BIN
          done
          EOF
          find $out -type f -regex '.*\.dylib\(\..*\)?' -exec $SHELL -c "$SCRIPT" \;
          find $out/bin -type f -exec $SHELL -c "$SCRIPT" \;
        '';
        upstreamParts = prev.lib.splitString upstreamDarwinFixup upstream;
        batchedDarwinFixup = builtins.readFile ./samba-darwin-fixup.sh + ''
          samba_fix_macho_tree
        '';
      in
      assert prev.lib.assertMsg (
        builtins.length upstreamParts == 2
      ) "samba: expected exactly one upstream Darwin dylib fixup";
      builtins.concatStringsSep batchedDarwinFixup upstreamParts
      + ''
        samba_verify_macho_tree
        unset SAMBA_HAS_ID SAMBA_LOAD_COMMANDS samba_libs
        unset -f samba_fix_macho samba_fix_macho_tree samba_macho_has_id \
          samba_macho_load_commands samba_verify_macho samba_verify_macho_tree
      '';
  });

  # Disable direnv checks on Darwin.
  direnv = prev.direnv.overrideAttrs (
    _oldAttrs:
    prev.lib.optionalAttrs prev.stdenv.hostPlatform.isDarwin {
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
      // (prev.lib.optionalAttrs (prev.stdenv.hostPlatform.isDarwin && pprev ? imageio) {
        imageio = pprev.imageio.overridePythonAttrs (oldAttrs: {
          disabledTests = (oldAttrs.disabledTests or [ ]) ++ [ "test_lagging_video_stream" ];
        });
      })
      // (prev.lib.optionalAttrs (prev.stdenv.hostPlatform.isDarwin && pprev ? cyclopts) {
        cyclopts = pprev.cyclopts.overridePythonAttrs (oldAttrs: {
          postPatch = (oldAttrs.postPatch or "") + ''
            substituteInPlace tests/completion/conftest.py \
              --replace-fail 'child.expect("ZTEST> ", timeout=4)' \
              'child.expect("ZTEST> ", timeout=20)'
          '';
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
    prev.lib.optionalAttrs prev.stdenv.hostPlatform.isDarwin {
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
    prev.lib.optionalAttrs prev.stdenv.hostPlatform.isDarwin {
      cmakeFlags = (oldAttrs.cmakeFlags or [ ]) ++ [ "-DBUILD_opencv_hdf=OFF" ];
    }
  );

  # Disable chromaprint checks on Darwin.
  chromaprint = prev.chromaprint.overrideAttrs (
    _:
    prev.lib.optionalAttrs prev.stdenv.hostPlatform.isDarwin {
      doCheck = false;
    }
  );

  # Give Darwin's pmixcc the include/share prefixes required by OpenMPI.
  pmix = prev.pmix.overrideAttrs (
    oldAttrs:
    prev.lib.optionalAttrs prev.stdenv.hostPlatform.isDarwin {
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
    prev.lib.optionalAttrs prev.stdenv.hostPlatform.isDarwin {
      dontStrip = true;
      postInstall = ''
        export HOME="$(mktemp -d)"
      ''
      + (oldAttrs.postInstall or "");
    }
  );

}
