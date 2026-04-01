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
      }
      // {

        mlx = pprev.mlx.overridePythonAttrs (
          oldAttrs:
          prev.lib.optionalAttrs (prev.stdenv.isDarwin && prev.stdenv.isAarch64) (
            let
              mlxMetalWheel = pfinal.fetchPypi {
                pname = "mlx_metal";
                version = "0.31.1";
                format = "wheel";
                dist = "py3";
                python = "py3";
                platform = "macosx_14_0_arm64";
                hash = "sha256-cHQRdBMdv3/dR5y3MOBuCMNY6sO/eQXZ6ITnlgz91bg=";
              };
            in
            {
              # Use pre-built wheel from PyPI that includes Metal support
              # Building from source fails in Nix sandbox due to Metal tools being unavailable
              version = "0.31.1";
              pyproject = null;
              format = "wheel";
              patches = [ ]; # Wheel doesn't need patches
              postPatch = ""; # No patching needed for pre-built wheel
              doCheck = false; # Wheels don't include tests
              # Skip mlx-metal dep check — its contents are merged in postInstall
              pythonRemoveDeps = [ "mlx-metal" ];
              src = pfinal.fetchPypi {
                pname = "mlx";
                version = "0.31.1";
                format = "wheel";
                dist = "cp313";
                python = "cp313";
                abi = "cp313";
                platform = "macosx_14_0_arm64";
                hash = "sha256-mm00EPyVG9KFCP7ZwatdmQP29rsQHDpdY9QZHUmjhKE=";
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
