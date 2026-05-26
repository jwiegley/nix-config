# overlays/30-ai-python.nix
# Purpose: Python package extensions for AI/ML tools
# Dependencies: None (uses only prev)
# Extends: pythonPackagesExtensions (mlx, llm-mlx, pymssql fixes, mitmproxy-macos)
final: prev:

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
      dependencies = [ mlx ];

      nativeCheckInputs = [
        pytestCheckHook
        pytest-asyncio
        pytest-recording
        writableTmpDirAsHomeHook
      ];

      pythonImportsCheck = [ "llm_mlx" ];

      passthru.tests = {
        llm-plugin = callPackage ./tests/llm-plugin.nix { };
      };

      meta = {
        description = "LLM access to models using MLX";
        homepage = "https://github.com/simonw/llm-mlx";
        changelog = "https://github.com/simonw/llm-mlx/releases/tag/${version}/CHANGELOG.md";
        license = lib.licenses.asl20;
        maintainers = with lib.maintainers; [ jwiegley ];
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
      }
      // {

        mlx = pprev.mlx.overridePythonAttrs (
          oldAttrs:
          prev.lib.optionalAttrs (prev.stdenv.isDarwin && prev.stdenv.isAarch64) (
            let
              mlxMetalWheel = pfinal.fetchPypi {
                pname = "mlx_metal";
                version = "0.31.2";
                format = "wheel";
                dist = "py3";
                python = "py3";
                platform = "macosx_14_0_arm64";
                hash = "sha256-slOFvO4Y/BlAkiVbi1O5o9hInrZQ5ZFg8bV6rdB6otw=";
              };
            in
            {
              # Use pre-built wheel from PyPI that includes Metal support
              # Building from source fails in Nix sandbox due to Metal tools being unavailable
              version = "0.31.2";
              pyproject = null;
              format = "wheel";
              patches = [ ]; # Wheel doesn't need patches
              postPatch = ""; # No patching needed for pre-built wheel
              doCheck = false; # Wheels don't include tests
              # Skip mlx-metal dep check — its contents are merged in postInstall
              pythonRemoveDeps = [ "mlx-metal" ];
              src = pfinal.fetchPypi {
                pname = "mlx";
                version = "0.31.2";
                format = "wheel";
                dist = "cp313";
                python = "cp313";
                abi = "cp313";
                platform = "macosx_14_0_arm64";
                hash = "sha256-Gz+w3alVsNVSzle91vQrMwmrIbBn5AWH1oSEQ9MH6R8=";
              };
              nativeBuildInputs = (oldAttrs.nativeBuildInputs or [ ]) ++ [ prev.unzip ];
              # Merge mlx-metal (Metal GPU kernels, split out since 0.31.x) into
              # this derivation to avoid namespace-package file collisions in buildEnv.
              postInstall = ''
                unzip -o ${mlxMetalWheel} -d $TMPDIR/mlx-metal
                siteDir=$out/lib/python3.13/site-packages/mlx
                cp -r $TMPDIR/mlx-metal/mlx/lib     $siteDir/
                cp -r $TMPDIR/mlx-metal/mlx/include  $siteDir/
                cp -r $TMPDIR/mlx-metal/mlx/share    $siteDir/
              '';
            }
          )
        );

        llm-mlx = pfinal.callPackage llm-mlx { };

        # omlx requires mlx_vlm.speculative (DDTree drafters), introduced
        # after the 0.4.4 release in nixpkgs. Pin to the 0.5.0 commit that
        # omlx itself pins (f96138e). mlx-audio is imported lazily inside
        # load_audio() and isn't packaged in nixpkgs, so drop that runtime
        # dep; llguidance (new in 0.5.0) is available in nixpkgs.
        mlx-vlm = pprev.mlx-vlm.overridePythonAttrs (oldAttrs: {
          version = "0.5.0";
          src = prev.fetchFromGitHub {
            owner = "Blaizzy";
            repo = "mlx-vlm";
            rev = "f96138eef1f5ce7fb5d97f8dd41a664a195b5659";
            hash = "sha256-Rz0t7g6qBcXS6IRwVyau410qpD3H3aEnLLvMenQ58Uc=";
          };
          dependencies = (oldAttrs.dependencies or [ ]) ++ [ pfinal.llguidance ];
          pythonRemoveDeps = (oldAttrs.pythonRemoveDeps or [ ]) ++ [ "mlx-audio" ];
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
        # (1ba6713, itself version 0.1.7) so the speculative-decode Metal
        # kernels match what omlx was tested against — the v0.1.7 release
        # tag is a slightly later commit.
        dflash-mlx = pfinal.buildPythonPackage rec {
          pname = "dflash-mlx";
          version = "0.1.7";
          pyproject = true;

          src = prev.fetchFromGitHub {
            owner = "bstnxbt";
            repo = "dflash-mlx";
            rev = "1ba671372b289c025b435c1a13aabb4bfb80b183";
            hash = "sha256-goVSVNnlC97SIs4zaczK0Yp4l+wkWpvN4mkDTmoPXB0=";
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
        ibis-framework = pprev.ibis-framework.overrideAttrs (old: {
          doCheck = false;
          doInstallCheck = false;
          installCheckPhase = "true";
          pythonImportsCheck = [ "ibis" ];
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
