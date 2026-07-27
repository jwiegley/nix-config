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

  passthru.tests.llm-plugin = callPackage ../overlays/tests/llm-plugin.nix { };

  meta = {
    description = "LLM access to models using MLX";
    homepage = "https://github.com/simonw/llm-mlx";
    changelog = "https://github.com/simonw/llm-mlx/releases/tag/${version}/CHANGELOG.md";
    license = lib.licenses.asl20;
  };
}
