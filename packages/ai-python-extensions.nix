# Python package extensions for AI/ML packages.
{ prev }:

let
  sources = import ./source-catalog.nix "ai";
  compatibilitySources = import ./source-catalog.nix "compatibility";
  mitmproxyMacosWheel = compatibilitySources.mitmproxy-macos-wheel;
in
[
  (
    pfinal: pprev:
    prev.lib.optionalAttrs prev.stdenv.isDarwin {
      # Fix hash mismatch for mitmproxy-macos wheel (PyPI republished the package)
      mitmproxy-macos = pprev.mitmproxy-macos.overridePythonAttrs (_oldAttrs: {
        inherit (mitmproxyMacosWheel) version;
        src =
          assert mitmproxyMacosWheel.source.fetcher == "fetchPypi";
          pfinal.fetchPypi mitmproxyMacosWheel.source.args;
      });

      # accelerate 1.13.0 added test_env_var_device, which mocks
      # torch.<device>.set_device. On Darwin <device> is "mps", but
      # torch 2.11.0 lacks torch.mps.set_device, so the patch() call
      # raises AttributeError before the mock can take effect.
      accelerate = pprev.accelerate.overridePythonAttrs (oldAttrs: {
        disabledTests = (oldAttrs.disabledTests or [ ]) ++ [
          "test_env_var_device"
        ];
      });

      # omlx 0.5.2 imports the Xet session-cancellation API added by this
      # matching huggingface-hub/hf-xet release pair.
      hf-xet = pprev.hf-xet.overridePythonAttrs (_oldAttrs: rec {
        inherit (sources.hf-xet) version;
        src =
          assert sources.hf-xet.source.fetcher == "fetchFromGitHub";
          prev.fetchFromGitHub sources.hf-xet.source.args;
        sourceRoot = "${src.name}/hf_xet";
        cargoDeps = prev.rustPlatform.fetchCargoVendor {
          pname = "hf-xet";
          inherit version src sourceRoot;
          hash = sources.hf-xet.hashes.cargoDepsHash;
        };
      });

      huggingface-hub = pprev.huggingface-hub.overridePythonAttrs (oldAttrs: rec {
        inherit (sources.huggingface-hub) version;
        src =
          assert sources.huggingface-hub.source.fetcher == "fetchFromGitHub";
          prev.fetchFromGitHub sources.huggingface-hub.source.args;
        postPatch = (oldAttrs.postPatch or "") + ''
          substituteInPlace src/huggingface_hub/cli/_cli_utils.py \
            --replace-fail "and error.possibilities:" "and getattr(error, 'possibilities', []):"
        '';
        pythonRelaxDeps = (oldAttrs.pythonRelaxDeps or [ ]) ++ [ "click" ];
        dependencies =
          map (dependency: if (dependency.pname or "") == "hf-xet" then pfinal.hf-xet else dependency) (
            oldAttrs.dependencies or [ ]
          )
          ++ [ pfinal.click ];
      });
    }
    // {

      mlx = pprev.mlx.overridePythonAttrs (
        oldAttrs:
        prev.lib.optionalAttrs (prev.stdenv.isDarwin && prev.stdenv.isAarch64) (
          let
            pythonTag = "cp${pfinal.python.sourceVersion.major}${pfinal.python.sourceVersion.minor}";
            wheelSources = sources.mlx.artifacts // {
              cp313 = sources.mlx.source;
            };
            mlxMetalWheel =
              assert sources.mlx.artifacts.metal.fetcher == "fetchPypi";
              pfinal.fetchPypi sources.mlx.artifacts.metal.args;
          in
          {
            # Use the pre-built wheel matching this package set's CPython
            # ABI. Building from source fails in the Nix sandbox because the
            # Metal toolchain is unavailable.
            inherit (sources.mlx) version;
            pyproject = null;
            format = "wheel";
            patches = [ ]; # Wheel doesn't need patches
            postPatch = ""; # No patching needed for pre-built wheel
            doCheck = false; # Wheels don't include tests
            # Skip mlx-metal dep check — its contents are merged in postInstall
            pythonRemoveDeps = [ "mlx-metal" ];
            src =
              let
                wheel = wheelSources.${pythonTag} or (throw "mlx has no wheel for ${pythonTag}");
              in
              assert wheel.fetcher == "fetchPypi";
              pfinal.fetchPypi wheel.args;
            nativeBuildInputs = (oldAttrs.nativeBuildInputs or [ ]) ++ [ prev.unzip ];
            # Merge mlx-metal (Metal GPU kernels, split out since 0.31.x) into
            # this derivation to avoid namespace-package file collisions in buildEnv.
            postInstall = ''
              unzip -o ${mlxMetalWheel} -d $TMPDIR/mlx-metal
              siteDir=$out/${pfinal.python.sitePackages}/mlx
              cp -r $TMPDIR/mlx-metal/mlx/lib     $siteDir/
              cp -r $TMPDIR/mlx-metal/mlx/include  $siteDir/
              cp -r $TMPDIR/mlx-metal/mlx/share    $siteDir/
            '';
          }
        )
      );

      inherit (pfinal.callPackage ./llm-mlx.nix { }) llm-mlx;

      # mlx-lm: nixpkgs ships the v0.31.3 release tag; omlx pins ab1806e
      # (tag + 15 commits), which adds the CVE-2026-5843 fix (model_file
      # execution gated behind trust_remote_code), the DeepSeek/GLM DSA
      # indexer RoPE fix, and Qwen 3.5 pipelining. Pin the exact commit
      # omlx was tested against. Keep in sync with the top-level mlx-lm
      # app in 30-ai-llm.nix.
      mlx-lm = pprev.mlx-lm.overridePythonAttrs (_oldAttrs: {
        inherit (sources.mlx-lm) version;
        src =
          assert sources.mlx-lm.source.fetcher == "fetchFromGitHub";
          prev.fetchFromGitHub sources.mlx-lm.source.args;
      });

      # omlx requires mlx_vlm.speculative (DDTree drafters), introduced
      # after the 0.4.4 release in nixpkgs. Pin to the exact commit omlx
      # 0.5.0 pins (78b96eb, upstream 0.6.3) — omlx vendors a MiniMax M3
      # compat patch written against this rev. llguidance and mlx-audio
      # are added below; mlx-audio is defined in this overlay.
      # python-multipart/starlette joined requirements.txt after 0.5.0;
      # starlette already propagates via fastapi.
      mlx-vlm = pprev.mlx-vlm.overridePythonAttrs (oldAttrs: {
        inherit (sources.mlx-vlm) version;
        src =
          assert sources.mlx-vlm.source.fetcher == "fetchFromGitHub";
          prev.fetchFromGitHub sources.mlx-vlm.source.args;
        dependencies = (oldAttrs.dependencies or [ ]) ++ [
          pfinal.llguidance
          pfinal.mlx-audio
          pfinal.python-multipart
        ];
        doCheck = false;
      });

      mlx-speech = pfinal.buildPythonPackage {
        pname = "mlx-speech";
        inherit (sources.mlx-speech) version;
        pyproject = true;

        src =
          assert sources.mlx-speech.source.fetcher == "fetchFromGitHub";
          prev.fetchFromGitHub sources.mlx-speech.source.args;

        postPatch = ''
          substituteInPlace pyproject.toml \
            --replace-fail "uv_build>=0.11.2,<0.12" "uv_build>=0.6"
        '';

        build-system = [ pfinal.uv-build ];

        dependencies = [
          pfinal.mlx
          pfinal.numpy
          pfinal.safetensors
          pfinal.soundfile
          pfinal.tokenizers
        ];

        pythonImportsCheck = [ "mlx_speech" ];

        meta = {
          description = "MLX-native speech library for Apple Silicon";
          homepage = "https://github.com/appautomaton/mlx-speech";
          license = prev.lib.licenses.mit;
        };
      };

      mlx-embeddings = pfinal.buildPythonPackage rec {
        pname = "mlx-embeddings";
        inherit (sources.mlx-embeddings) version;
        format = "wheel";

        src =
          assert sources.mlx-embeddings.source.fetcher == "fetchurl";
          prev.fetchurl sources.mlx-embeddings.source.args;

        dependencies = with pfinal; [
          mlx
          mlx-vlm
          transformers
          huggingface-hub
          sentencepiece
        ];

        pythonImportsCheck = [ "mlx_embeddings" ];

        meta = {
          description = "MLX-based text embeddings for Apple Silicon";
          homepage = "https://github.com/Blaizzy/mlx-embeddings";
          license = prev.lib.licenses.asl20;
        };
      };

      # dflash-mlx - lossless DFlash speculative decoding for MLX.
      # Required by omlx; not in nixpkgs. Pin the exact fork and commit omlx pins
      # (474f8e1, version 0.1.10+omlx.3: Apple G17 NAX verify, prefix snapshot
      # metrics, CopySpec mode, full-context draft-layer cache checks) so
      # the speculative-decode kernels match what omlx was tested against.
      dflash-mlx = pfinal.buildPythonPackage rec {
        pname = "dflash-mlx";
        inherit (sources.dflash-mlx) version;
        pyproject = true;

        src =
          assert sources.dflash-mlx.source.fetcher == "fetchFromGitHub";
          prev.fetchFromGitHub sources.dflash-mlx.source.args;

        build-system = [ pfinal.setuptools ];

        dependencies = with pfinal; [
          mlx
          mlx-lm
        ];

        pythonImportsCheck = [ "dflash_mlx" ];

        meta = {
          description = "Lossless DFlash speculative decoding for MLX on Apple Silicon";
          homepage = "https://github.com/bstnxbt/dflash-mlx";
          license = prev.lib.licenses.asl20;
          platforms = [ "aarch64-darwin" ];
        };
      };

      # ── mlx-audio and its missing dependencies ──────────────────────
      # omlx's [audio] extra (tts/stt/sts) pulls mlx-audio, which in turn
      # needs three packages absent from nixpkgs: pyloudnorm,
      # phonemizer-fork, and espeakng-loader.

      # dlinfo (phonemizer / phonemizer-fork dep) is flagged broken on
      # Darwin in nixpkgs. The package itself works on Mac (it uses
      # dyld_find); only its glibc-specific test suite — which probes for
      # libc.so/libdl.so by Linux soname — fails. Unbreak it and skip the
      # inapplicable tests, keeping the import check.
      dlinfo = pprev.dlinfo.overridePythonAttrs (old: {
        doCheck = false;
        pythonImportsCheck = (old.pythonImportsCheck or [ ]) ++ [ "dlinfo" ];
        meta = old.meta // {
          broken = false;
        };
      });

      # frictionless adds every optional extra to its check inputs, including
      # the top-level visidata package built with the default Python. OMLX's
      # Python 3.13 audio closure does not use that optional integration, so
      # keep its install checks while removing only the cross-ABI check edge.
      frictionless = pprev.frictionless.overridePythonAttrs (
        oldAttrs:
        prev.lib.optionalAttrs (pfinal.python.pythonVersion == "3.13") {
          nativeCheckInputs = builtins.filter (input: prev.lib.getName input != "visidata") (
            oldAttrs.nativeCheckInputs or [ ]
          );
        }
      );

      # pdfplumber lists pandas-stubs as a development dependency, but its Nix
      # check phase only runs pytest (not mypy). Avoid building the outdated
      # stubs against Pandas 3 for OMLX's Python 3.13 closure.
      pdfplumber = pprev.pdfplumber.overridePythonAttrs (
        oldAttrs:
        prev.lib.optionalAttrs (pfinal.python.pythonVersion == "3.13") {
          nativeCheckInputs = builtins.filter (input: prev.lib.getName input != "pandas-stubs") (
            oldAttrs.nativeCheckInputs or [ ]
          );
        }
      );

      pyloudnorm = pfinal.buildPythonPackage rec {
        pname = "pyloudnorm";
        inherit (sources.pyloudnorm) version;
        pyproject = true;

        src =
          assert sources.pyloudnorm.source.fetcher == "fetchPypi";
          pfinal.fetchPypi sources.pyloudnorm.source.args;

        build-system = [ pfinal.setuptools ];
        dependencies = with pfinal; [
          numpy
          scipy
        ];

        pythonImportsCheck = [ "pyloudnorm" ];

        meta = {
          description = "Implementation of ITU-R BS.1770-4 loudness algorithm";
          homepage = "https://github.com/csteinmetz1/pyloudnorm";
          license = prev.lib.licenses.mit;
        };
      };

      # phonemizer-fork is a maintained fork of phonemizer; it imports as
      # the `phonemizer` namespace and locates espeak-ng via espeakng-loader.
      phonemizer-fork = pfinal.buildPythonPackage rec {
        pname = "phonemizer-fork";
        inherit (sources.phonemizer-fork) version;
        pyproject = true;

        src =
          assert sources.phonemizer-fork.source.fetcher == "fetchPypi";
          pfinal.fetchPypi sources.phonemizer-fork.source.args;

        build-system = [ pfinal.hatchling ];
        dependencies = with pfinal; [
          attrs
          dlinfo
          joblib
          segments
          typing-extensions
        ];

        pythonImportsCheck = [ "phonemizer" ];

        meta = {
          description = "Simple text-to-phonemes converter for multiple languages (maintained fork)";
          homepage = "https://github.com/bootphon/phonemizer";
          license = prev.lib.licenses.gpl3Only;
        };
      };

      # espeakng-loader ships a prebuilt espeak-ng inside the wheel and
      # exposes its library/data paths. Use the arm64 macOS wheel.
      espeakng-loader = pfinal.buildPythonPackage rec {
        pname = "espeakng-loader";
        inherit (sources.espeakng-loader) version;
        format = "wheel";

        src =
          assert sources.espeakng-loader.source.fetcher == "fetchPypi";
          pfinal.fetchPypi sources.espeakng-loader.source.args;

        pythonImportsCheck = [ "espeakng_loader" ];

        meta = {
          description = "Loader providing a bundled espeak-ng library and data";
          homepage = "https://github.com/thewh1teagle/espeakng-loader";
          license = prev.lib.licenses.mit;
          platforms = [ "aarch64-darwin" ];
        };
      };

      cohere-melody =
        let
          pythonTag = "cp${pfinal.python.sourceVersion.major}${pfinal.python.sourceVersion.minor}";
          wheelSources = sources.cohere-melody.artifacts // {
            cp313 = sources.cohere-melody.source;
          };
        in
        pfinal.buildPythonPackage rec {
          pname = "cohere-melody";
          inherit (sources.cohere-melody) version;
          format = "wheel";

          # Melody is a native Rust extension. Select the wheel matching the
          # package set instead of installing a CPython 3.13 module into 3.14.
          src =
            let
              wheel = wheelSources.${pythonTag} or (throw "cohere-melody has no wheel for ${pythonTag}");
            in
            assert wheel.fetcher == "fetchPypi";
            pfinal.fetchPypi wheel.args;

          pythonImportsCheck = [ "cohere_melody" ];

          meta = {
            description = "Templating rendering and generation parsing for Cohere models";
            homepage = "https://github.com/cohere-ai/melody";
            license = prev.lib.licenses.mit;
            platforms = [ "aarch64-darwin" ];
          };
        };

      # mlx-audio - TTS/STT/STS inference for Apple Silicon. Pinned to the
      # exact commit omlx pins. mlx-lm is pinned ==0.31.1 upstream; relax
      # it to use our 0.31.3. Runtime dep check is skipped because the
      # [audio] extras resolve through optional namespaces.
      mlx-audio = pfinal.buildPythonPackage rec {
        pname = "mlx-audio";
        inherit (sources.mlx-audio) version;
        pyproject = true;

        src =
          assert sources.mlx-audio.source.fetcher == "fetchFromGitHub";
          prev.fetchFromGitHub sources.mlx-audio.source.args;

        build-system = [
          pfinal.setuptools
          pfinal.wheel
        ];

        dontCheckRuntimeDeps = true;

        dependencies = with pfinal; [
          # core
          mlx
          numpy
          huggingface-hub
          transformers
          mlx-lm
          tqdm
          sounddevice
          miniaudio
          pyloudnorm
          numba
          librosa
          protobuf
          # tts + stt + sts extras
          tiktoken
          mistral-common
          sentencepiece
          misaki
          num2words
          phonemizer-fork
          espeakng-loader
          webrtcvad
        ];

        pythonImportsCheck = [ "mlx_audio" ];

        meta = {
          description = "TTS/STT/STS inference for Apple Silicon via MLX";
          homepage = "https://github.com/Blaizzy/mlx-audio";
          license = prev.lib.licenses.mit;
          platforms = [ "aarch64-darwin" ];
        };
      };

      # standard-distutils: backport of distutils for Python 3.12+
      standard-distutils = pfinal.buildPythonPackage rec {
        pname = "standard-distutils";
        inherit (sources.standard-distutils) version;
        pyproject = true;

        src =
          assert sources.standard-distutils.source.fetcher == "fetchPypi";
          prev.fetchPypi sources.standard-distutils.source.args;

        build-system = [ pfinal.setuptools ];

        pythonImportsCheck = [ "distutils" ];

        meta = {
          description = "Redistribution of removed distutils module from stdlib";
          homepage = "https://pypi.org/project/standard-distutils/";
          license = prev.lib.licenses.psfl;
        };
      };

      # sanic test_validate_group_sets_gid fails in Nix sandbox (no 'root' group)
      sanic = pprev.sanic.overridePythonAttrs (_: {
        doCheck = false;
      });

      # ibis-framework: DuckDB backend tests fail (SystemError) and pythonImportsCheck
      # tries to import ibis.backends.duckdb which needs the optional duckdb module
      ibis-framework = pprev.ibis-framework.overrideAttrs (_old: {
        doCheck = false;
        doInstallCheck = false;
        installCheckPhase = "true";
        pythonImportsCheck = [ "ibis" ];
      });

      xarray = pprev.xarray.overridePythonAttrs (_: {
        doCheck = false;
        doInstallCheck = false;
        pythonImportsCheck = [ ];
      });

      spacy = pprev.spacy.overridePythonAttrs (_: {
        doCheck = false;
        doInstallCheck = false;
        pythonImportsCheck = [ ];
      });

      aiologic = pfinal.buildPythonPackage rec {
        pname = "aiologic";
        inherit (sources.aiologic) version;
        format = "wheel";

        src =
          assert sources.aiologic.source.fetcher == "fetchPypi";
          pfinal.fetchPypi sources.aiologic.source.args;

        dependencies = with pfinal; [
          sniffio
          typing-extensions
          wrapt
        ];

        pythonImportsCheck = [ "aiologic" ];

        meta = {
          description = "Synchronization primitives for tasks and threads";
          homepage = "https://pypi.org/project/aiologic/";
          license = prev.lib.licenses.mit;
        };
      };

      culsans = pfinal.buildPythonPackage rec {
        pname = "culsans";
        inherit (sources.culsans) version;
        format = "wheel";

        src =
          assert sources.culsans.source.fetcher == "fetchPypi";
          pfinal.fetchPypi sources.culsans.source.args;

        dependencies = with pfinal; [
          aiologic
          typing-extensions
        ];

        pythonImportsCheck = [ "culsans" ];

        meta = {
          description = "Mixed sync-async queue for threaded and async communication";
          homepage = "https://pypi.org/project/culsans/";
          license = prev.lib.licenses.asl20;
        };
      };

      # Fix pymssql: upstream changed setuptools constraint from ">=54.0,<70.3" to ">80.0"
      # and now requires standard-distutils for Python 3.12+
      pymssql = pprev.pymssql.overridePythonAttrs (oldAttrs: {
        postPatch = ''
          substituteInPlace pyproject.toml \
            --replace-fail "setuptools>80.0" "setuptools"
        '';
        build-system = (oldAttrs.build-system or [ ]) ++ [ pfinal.standard-distutils ];
      });
    }
  )
]
