self: super:

let
  llm-mlx = {
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

mlx-lm = with self; with self.python3Packages; buildPythonApplication rec {
  pname = "mlx-lm";
  version = "0.24.1";
  pyproject = true;

  src = fetchFromGitHub {
    owner = "mlx-explore";
    repo = "mlx-lm";
    tag = version;
    hash = "sha256-8SGbvhuNeKgMYGa0ZiOLm+H/JbNpvFWBcUL4De5xO4o=";
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

  meta = {
    description = "LLM access to models using MLX";
    homepage = "https://github.com/mlx-explore/mlx-lm";
    license = lib.licenses.mit;
    maintainers = with lib.maintainers; [ jwiegley ];
  };
};

pythonPackagesExtensions = (super.pythonPackagesExtensions or []) ++ [
  (pfinal: pprev:
    let
      nanobind = pprev.nanobind.overridePythonAttrs (oldAttrs: rec {
        version = "2.4.0";
        src = super.fetchFromGitHub {
          owner = "wjakob";
          repo = "nanobind";
          rev = "v${version}";
          fetchSubmodules = true;
          hash = "sha256-9OpDsjFEeJGtbti4Q9HHl78XaGf8M3lG4ukvHCMzyMU=";
        };
      });
   in {
    mlx = pprev.mlx.overridePythonAttrs (oldAttrs: rec {
      # version = "0.25.2";
      # src = super.fetchFromGitHub {
      #   owner = "ml-explore";
      #   repo = "mlx";
      #   rev = "refs/tags/v${version}";
      #   hash = "sha256-fkf/kKATr384WduFG/X81c5InEAZq5u5+hwrAJIg7MI=";
      # };
      patches = [];
      env = {
        PYPI_RELEASE = oldAttrs.version;
        CMAKE_ARGS = with self; toString [
          # (lib.cmakeBool "MLX_BUILD_METAL" true)
          (lib.cmakeOptionType "filepath" "FETCHCONTENT_SOURCE_DIR_GGUFLIB" "${gguf-tools}")
          (lib.cmakeOptionType "filepath" "FETCHCONTENT_SOURCE_DIR_JSON" "${nlohmann_json}")
        ];
      };
      # buildInputs = (oldAttrs.buildInputs or []) ++ [
      #   self.darwin.apple_sdk_14_4
      # ];
      # nativeBuildInputs = (oldAttrs.nativeBuildInputs or []) ++ [
      #   nanobind
      # ];
    });

    llm-mlx = pfinal.callPackage llm-mlx {};
  })
];

}
