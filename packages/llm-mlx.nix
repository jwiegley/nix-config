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

let
  sources = import ./source-catalog.nix "ai";
in
{
  llm-mlx = buildPythonPackage rec {
    pname = "llm-mlx";
    version = sources.llm-mlx.version;
    pyproject = true;

    src =
      assert sources.llm-mlx.source.fetcher == "fetchFromGitHub";
      fetchFromGitHub sources.llm-mlx.source.args;

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

    passthru.tests.llm-plugin = callPackage ../test/ai/overlays/llm-plugin.nix { };

    meta = {
      description = "LLM access to models using MLX";
      homepage = "https://github.com/simonw/llm-mlx";
      changelog = "https://github.com/simonw/llm-mlx/releases/tag/${version}/CHANGELOG.md";
      license = lib.licenses.asl20;
    };
  };
}
