# Python package extensions for AI/ML packages.
{ prev }:

let
  sources = import ./source-catalog.nix "ai";
in
[
  (
    pfinal: pprev:
    prev.lib.optionalAttrs prev.stdenv.hostPlatform.isDarwin {
      # Keep huggingface-hub and hf-xet on the catalog-pinned release pair.
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
        prev.lib.optionalAttrs (prev.stdenv.hostPlatform.isDarwin && prev.stdenv.isAarch64) (
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
            # Select the prebuilt wheel matching this package set's CPython ABI.
            inherit (sources.mlx) version;
            pyproject = null;
            format = "wheel";
            patches = [ ];
            postPatch = "";
            doCheck = false;
            # Skip mlx-metal dep check — its contents are merged in postInstall
            pythonRemoveDeps = [ "mlx-metal" ];
            src =
              let
                wheel = wheelSources.${pythonTag} or (throw "mlx has no wheel for ${pythonTag}");
              in
              assert wheel.fetcher == "fetchPypi";
              pfinal.fetchPypi wheel.args;
            nativeBuildInputs = (oldAttrs.nativeBuildInputs or [ ]) ++ [ prev.unzip ];
            # Merge the separate mlx-metal wheel into this derivation to avoid
            # namespace-package file collisions in buildEnv.
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

      # Share the catalog-pinned mlx-lm revision with the top-level application.
      mlx-lm = pprev.mlx-lm.overridePythonAttrs (_oldAttrs: {
        inherit (sources.mlx-lm) version;
        src =
          assert sources.mlx-lm.source.fetcher == "fetchFromGitHub";
          prev.fetchFromGitHub sources.mlx-lm.source.args;
      });

      # Use the catalog-pinned mlx-vlm revision and explicit optional dependencies.
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

      # Build the catalog-pinned dflash-mlx fork for speculative decoding.
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

      # ── mlx-audio dependency closure ─────────────────────────────────

      # dlinfo's Linux-soname tests fail on Darwin; retain the macOS tests and
      # import check while enabling the package for this closure.
      dlinfo = pprev.dlinfo.overridePythonAttrs (old: {
        disabledTestPaths = (old.disabledTestPaths or [ ]) ++ [ "tests/dlinfo_glibc_test.py" ];
        meta = old.meta // {
          broken = false;
        };
      });

      # Remove the cross-ABI visidata check input from the Python 3.13 closure.
      frictionless = pprev.frictionless.overridePythonAttrs (
        oldAttrs:
        prev.lib.optionalAttrs (pfinal.python.pythonVersion == "3.13") {
          nativeCheckInputs = builtins.filter (input: prev.lib.getName input != "visidata") (
            oldAttrs.nativeCheckInputs or [ ]
          );
        }
      );

      # Remove the unused pandas-stubs check input from the Python 3.13 closure.
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

      # phonemizer-fork installs the `phonemizer` namespace.
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

      # mlx-audio - TTS/STT/STS inference for Apple Silicon. The source catalog
      # owns this pin independently of omlx's audio extra.
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

        # Runtime metadata constraints do not match this package set, so provide
        # explicit dependencies below and skip the generic metadata check.
        dontCheckRuntimeDeps = true;

        dependencies = with pfinal; [
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

      # Disable ibis checks and optional-backend import checks for this closure.
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

      # Relax pymssql's setuptools constraint and supply standard-distutils.
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
