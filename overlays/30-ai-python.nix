# overlays/30-ai-python.nix
# Purpose: Python package extensions for AI/ML tools
# Dependencies: None (uses only prev)
# Extends: pythonPackagesExtensions (mlx, llm-mlx, pymssql fixes, mitmproxy-macos)
final: prev:

let
  llm-mlx = { lib, callPackage, buildPythonPackage, fetchFromGitHub, setuptools
    , llm, mlx, pytestCheckHook, pytest-asyncio, pytest-recording
    , writableTmpDirAsHomeHook, }:
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

      build-system = [ setuptools llm ];
      dependencies = [ mlx ];

      nativeCheckInputs = [
        pytestCheckHook
        pytest-asyncio
        pytest-recording
        writableTmpDirAsHomeHook
      ];

      pythonImportsCheck = [ "llm_mlx" ];

      passthru.tests = { llm-plugin = callPackage ./tests/llm-plugin.nix { }; };

      meta = {
        description = "LLM access to models using MLX";
        homepage = "https://github.com/simonw/llm-mlx";
        changelog =
          "https://github.com/simonw/llm-mlx/releases/tag/${version}/CHANGELOG.md";
        license = lib.licenses.asl20;
        maintainers = with lib.maintainers; [ jwiegley ];
      };
    };
in {

  pythonPackagesExtensions = (prev.pythonPackagesExtensions or [ ]) ++ [
    (pfinal: pprev:
      let
        nanobind = pprev.nanobind.overridePythonAttrs (oldAttrs: rec {
          version = "2.4.0";
          src = prev.fetchFromGitHub {
            owner = "wjakob";
            repo = "nanobind";
            rev = "v${version}";
            fetchSubmodules = true;
            hash = "sha256-9OpDsjFEeJGtbti4Q9HHl78XaGf8M3lG4ukvHCMzyMU=";
          };
        });
      in {
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

        mlx = pprev.mlx.overridePythonAttrs (oldAttrs: {
          # Use pre-built wheel from PyPI that includes Metal support
          # Building from source fails in Nix sandbox due to Metal tools being unavailable
          version = "0.30.0";
          pyproject = null;
          format = "wheel";
          patches = [ ]; # Wheel doesn't need patches
          postPatch = ""; # No patching needed for pre-built wheel
          doCheck = false; # Wheels don't include tests
          src = pfinal.fetchPypi {
            pname = "mlx";
            version = "0.30.0";
            format = "wheel";
            dist = "cp313";
            python = "cp313";
            abi = "cp313";
            platform = "macosx_14_0_arm64";
            hash = "sha256-9GqqbFYroYPipkoOa6Fe1U+QJ9m3sYIunux/WbE9YQw=";
          };
        });

        llm-mlx = pfinal.callPackage llm-mlx { };

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
            description =
              "Redistribution of removed distutils module from stdlib";
            homepage = "https://pypi.org/project/standard-distutils/";
            license = prev.lib.licenses.psfl;
          };
        };

        # Fix pymssql: upstream changed setuptools constraint from ">=54.0,<70.3" to ">80.0"
        # and now requires standard-distutils for Python 3.12+
        pymssql = pprev.pymssql.overridePythonAttrs (oldAttrs: {
          postPatch = ''
            substituteInPlace pyproject.toml \
              --replace-fail "setuptools>80.0" "setuptools"
          '';
          build-system = (oldAttrs.build-system or [ ])
            ++ [ pfinal.standard-distutils ];
        });
      })
  ];

}
