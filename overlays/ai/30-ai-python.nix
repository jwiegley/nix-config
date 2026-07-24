# overlays/30-ai-python.nix
# Purpose: Python package extensions for AI/ML tools
# Dependencies: None (uses only prev)
# Extends: pythonPackagesExtensions (mlx, llm-mlx, pymssql fixes, mitmproxy-macos)
_final: prev:

let
  llm-mlx =
    {
      lib,
      callPackage,
      buildPythonPackage,
      fetchFromGitHub,
      setuptools,
      llm,
      mlx,
      mlx-lm,
      pytestCheckHook,
      pytest-asyncio,
      pytest-recording,
      writableTmpDirAsHomeHook,
    }:
    buildPythonPackage rec {
      pname = "llm-mlx";
      version = "0.4";
      pyproject = true;

      src = fetchFromGitHub {
        owner = "simonw";
        repo = "llm-mlx";
        tag = version;
        hash = "sha256-9SGbvhuNeKgMYGa0ZiOLm+H/JbNpvFWBcUL4De5xO4o=";
      };

      build-system = [
        setuptools
        llm
      ];
      dependencies = [
        mlx
        mlx-lm
      ];

      nativeCheckInputs = [
        pytestCheckHook
        pytest-asyncio
        pytest-recording
        writableTmpDirAsHomeHook
      ];

      pythonImportsCheck = [ "llm_mlx" ];

      passthru.tests = {
        llm-plugin = callPackage ../tests/llm-plugin.nix { };
      };

      meta = {
        description = "LLM access to models using MLX";
        homepage = "https://github.com/simonw/llm-mlx";
        changelog = "https://github.com/simonw/llm-mlx/releases/tag/${version}/CHANGELOG.md";
        license = lib.licenses.asl20;
      };
    };
in
{

  pythonPackagesExtensions = (prev.pythonPackagesExtensions or [ ]) ++ [
    (
      pfinal: pprev:
      prev.lib.optionalAttrs prev.stdenv.isDarwin {
        # Fix hash mismatch for mitmproxy-macos wheel (PyPI republished the package)
        mitmproxy-macos = pprev.mitmproxy-macos.overridePythonAttrs (oldAttrs: {
          src = pfinal.fetchPypi {
            pname = "mitmproxy_macos";
            inherit (oldAttrs) version;
            format = "wheel";
            dist = "py3";
            python = "py3";
            hash = "sha256-baAfEY4hEN3wOEicgE53gY71IX003JYFyyZaNJ7U8UA=";
          };
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
          version = "1.5.1";
          src = prev.fetchFromGitHub {
            owner = "huggingface";
            repo = "xet-core";
            tag = "v${version}";
            hash = "sha256-TqSErydAOaHzCN7qglO/aqMF8BWYXvEv09adhxTwny0=";
          };
          sourceRoot = "${src.name}/hf_xet";
          cargoDeps = prev.rustPlatform.fetchCargoVendor {
            pname = "hf-xet";
            inherit version src sourceRoot;
            hash = "sha256-pwHUIkx+Dk8fGOVxRJKLswLjQB+sKzpyOOeqV6+Xyxo=";
          };
        });

        huggingface-hub = pprev.huggingface-hub.overridePythonAttrs (oldAttrs: rec {
          version = "1.19.0";
          src = prev.fetchFromGitHub {
            owner = "huggingface";
            repo = "huggingface_hub";
            tag = "v${version}";
            hash = "sha256-gFOeYwsZTlXSgnuYsUqLv2OB8rsiI5QIeZFY8mH+Ke8=";
          };
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
              wheelHashes = {
                cp311 = "sha256-csYFNo0UXHVodwV9fjxU8WnJiZ/h+DIyv7OmNCVh4jQ=";
                cp312 = "sha256-6lpZQ1XInACV6rpBP9OdTKqGQvoTQy37DJNU0UEEZGc=";
                cp313 = "sha256-q7eG7h6WOHWb6CWDIi/H0JxWUO+QrSt8XafRkxqGdtw=";
                cp314 = "sha256-LuebH4wsKjKa/JXs59zgvnmNQ/PedxpjcNK5+XArvZo=";
              };
              mlxMetalWheel = pfinal.fetchPypi {
                pname = "mlx_metal";
                version = "0.32.0";
                format = "wheel";
                dist = "py3";
                python = "py3";
                platform = "macosx_14_0_arm64";
                hash = "sha256-W2SyCsJLDEAfSJ3gHoIJ7cTTchJSAfGTFObznjhTIqo=";
              };
            in
            {
              # Use the pre-built wheel matching this package set's CPython
              # ABI. Building from source fails in the Nix sandbox because the
              # Metal toolchain is unavailable.
              version = "0.32.0";
              pyproject = null;
              format = "wheel";
              patches = [ ]; # Wheel doesn't need patches
              postPatch = ""; # No patching needed for pre-built wheel
              doCheck = false; # Wheels don't include tests
              # Skip mlx-metal dep check — its contents are merged in postInstall
              pythonRemoveDeps = [ "mlx-metal" ];
              src = pfinal.fetchPypi {
                pname = "mlx";
                version = "0.32.0";
                format = "wheel";
                dist = pythonTag;
                python = pythonTag;
                abi = pythonTag;
                platform = "macosx_14_0_arm64";
                hash = wheelHashes.${pythonTag} or (throw "mlx has no wheel for ${pythonTag}");
              };
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

        llm-mlx = pfinal.callPackage llm-mlx { };

        # mlx-lm: nixpkgs ships the v0.31.3 release tag; omlx pins ab1806e
        # (tag + 15 commits), which adds the CVE-2026-5843 fix (model_file
        # execution gated behind trust_remote_code), the DeepSeek/GLM DSA
        # indexer RoPE fix, and Qwen 3.5 pipelining. Pin the exact commit
        # omlx was tested against. Keep in sync with the top-level mlx-lm
        # app in 30-ai-llm.nix.
        mlx-lm = pprev.mlx-lm.overridePythonAttrs (_oldAttrs: {
          version = "0.31.3-unstable-2026-07-07";
          src = prev.fetchFromGitHub {
            owner = "ml-explore";
            repo = "mlx-lm";
            rev = "ab1806e8f5d6aa035973af194a1b9198ab4754dc";
            hash = "sha256-C8KF9q/gxR+YTH8Pg9qmQ/mFnVHQ30vl4BBUQl8IPP4=";
          };
        });

        # omlx requires mlx_vlm.speculative (DDTree drafters), introduced
        # after the 0.4.4 release in nixpkgs. Pin to the exact commit omlx
        # 0.5.0 pins (78b96eb, upstream 0.6.3) — omlx vendors a MiniMax M3
        # compat patch written against this rev. llguidance and mlx-audio
        # are added below; mlx-audio is defined in this overlay.
        # python-multipart/starlette joined requirements.txt after 0.5.0;
        # starlette already propagates via fastapi.
        mlx-vlm = pprev.mlx-vlm.overridePythonAttrs (oldAttrs: {
          version = "0.6.3";
          src = prev.fetchFromGitHub {
            owner = "Blaizzy";
            repo = "mlx-vlm";
            rev = "78b96eb5462141447b9a6b4943ef553891da56dd";
            hash = "sha256-JEECMpjP7YK2Y59g54KVWtBKZsfB+rOK4dQlPabLjF8=";
          };
          dependencies = (oldAttrs.dependencies or [ ]) ++ [
            pfinal.llguidance
            pfinal.mlx-audio
            pfinal.python-multipart
          ];
          doCheck = false;
        });

        mlx-speech = pfinal.buildPythonPackage {
          pname = "mlx-speech";
          version = "0-unstable-2025-03-30";
          pyproject = true;

          src = prev.fetchFromGitHub {
            owner = "appautomaton";
            repo = "mlx-speech";
            rev = "d7bb3d79fe7b6cf545a79ca6ebfb0c22c221f6ad";
            hash = "sha256-083qJM0aXQmc0Yu+MW8a9MuzCDiye9AZHghP0Pgmr2s=";
          };

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
          version = "0.1.0";
          format = "wheel";

          src = prev.fetchurl {
            url = "https://files.pythonhosted.org/packages/78/18/05a341c811c9ee04f227cdbc064a635b84202cb8f85471adfdeebe0da32d/mlx_embeddings-${version}-py2.py3-none-any.whl";
            hash = "sha256-P+H+qnhtO1RszYkJ9rTCK9O8zgl2FvzoMXPt7dMOZjA=";
          };

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
        # Required by omlx; not in nixpkgs. Pin the exact commit omlx pins
        # (9ca0028, version 0.1.10: Apple G17 NAX verify, prefix snapshot
        # metrics, CopySpec mode, full-context draft-layer cache checks) so
        # the speculative-decode kernels match what omlx was tested against.
        dflash-mlx = pfinal.buildPythonPackage rec {
          pname = "dflash-mlx";
          version = "0.1.10";
          pyproject = true;

          src = prev.fetchFromGitHub {
            owner = "bstnxbt";
            repo = "dflash-mlx";
            rev = "9ca002898b48e14c9727dec17299f497e8467870";
            hash = "sha256-qhbmkL0Ay9aF1tjZP5bLbqh33969hE6rA41XlaB2Vvs=";
          };

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
          version = "0.2.0";
          pyproject = true;

          src = pfinal.fetchPypi {
            inherit pname version;
            hash = "sha256-i/WXZY6k4ZdcJ1rfSQ9t61Np6kCfKQH5OZFe+ktoGxY=";
          };

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
          version = "3.3.2";
          pyproject = true;

          src = pfinal.fetchPypi {
            pname = "phonemizer_fork";
            inherit version;
            hash = "sha256-EOFugn0EQ7CHBi4htV6AXACYnPE0Oy6B5zTK5fbAz2k=";
          };

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
          version = "0.2.4";
          format = "wheel";

          src = pfinal.fetchPypi {
            pname = "espeakng_loader";
            inherit version;
            format = "wheel";
            dist = "py3";
            python = "py3";
            abi = "none";
            platform = "macosx_11_0_arm64";
            hash = "sha256-0nzcoxESIm5ymdhWLoidPjih5IBVye44G0XWaQcu5Z8=";
          };

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
            wheelHashes = {
              cp311 = "sha256-4J4083no3JSGfKd8vWOIWQoLmICaEwrXDKIfhqU3sxo=";
              cp312 = "sha256-82DpFigLhoT/KQTVZk4/AnlVqO7hwGCSMjlulsfQB6o=";
              cp313 = "sha256-gU6PlYufxOy6AnmNlHsdIQrP8wnISRl2+AIR0wV5jac=";
              cp314 = "sha256-YHOU39HJ+Noyu7tbD0W0quP3ghXRzYHok4TER5V3Ggc=";
            };
          in
          pfinal.buildPythonPackage rec {
            pname = "cohere-melody";
            version = "0.9.0";
            format = "wheel";

            # Melody is a native Rust extension. Select the wheel matching the
            # package set instead of installing a CPython 3.13 module into 3.14.
            src = pfinal.fetchPypi {
              pname = "cohere_melody";
              inherit version;
              format = "wheel";
              dist = pythonTag;
              python = pythonTag;
              abi = pythonTag;
              platform = "macosx_11_0_arm64";
              hash = wheelHashes.${pythonTag} or (throw "cohere-melody has no wheel for ${pythonTag}");
            };

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
          version = "0.4.3";
          pyproject = true;

          src = prev.fetchFromGitHub {
            owner = "Blaizzy";
            repo = "mlx-audio";
            rev = "51753266e0a4f766fd5e6fbc46652224efc23981";
            hash = "sha256-2MbcOFk/lx1UNqFlyxYl03cL8yFUprZdgcb6eo5SX6w=";
          };

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
          version = "3.11.9";
          pyproject = true;

          src = prev.fetchPypi {
            pname = "standard_distutils";
            inherit version;
            hash = "sha256-N9bJ8PAyHtPJySPlSw/br6PXv1VoId5V/YFY1/RA3rU=";
          };

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
          version = "0.16.0";
          format = "wheel";

          src = pfinal.fetchPypi {
            inherit pname version;
            format = "wheel";
            dist = "py3";
            python = "py3";
            hash = "sha256-4Azl9oxWB8hk0mrsmcCjOoO9+CN6pzEv+7loBa9n2LY=";
          };

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
          version = "0.10.0";
          format = "wheel";

          src = pfinal.fetchPypi {
            inherit pname version;
            format = "wheel";
            dist = "py3";
            python = "py3";
            hash = "sha256-6DLJY1q3AWz2JWXeKUJp9HCM2SIA0A2v3S5aGUNYfy4=";
          };

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
  ];

}
