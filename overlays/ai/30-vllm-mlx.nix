# Purpose: vLLM-like inference for Apple Silicon via MLX
# Dependencies: Uses final for python3Packages (needs mlx, mlx-embeddings from extensions)
# Packages: vllm-mlx
final: prev:
let
  source = (import ../../packages/source-catalog.nix "ai").vllm-mlx;
in
{

  vllm-mlx =
    let
      inherit (final) python3Packages;
      gradioForVllm =
        (python3Packages.gradio.override { inherit (python3Packages) gradio; }).overridePythonAttrs
          (oldAttrs: {
            # huggingface_hub probes its online agent registry while building
            # request headers. Keep Gradio's sandboxed test suite offline.
            env = (oldAttrs.env or { }) // {
              HF_HUB_OFFLINE = "1";
            };

            # Gradio allows Starlette 1.x at runtime, but its wheel
            # metadata still says starlette<1.0. nixpkgs currently ships
            # starlette 1.1.0.
            dontCheckRuntimeDeps = true;
          });
    in
    with final;
    with python3Packages;
    buildPythonApplication rec {
      pname = "vllm-mlx";
      inherit (source) version;
      pyproject = null;
      format = "wheel";

      src =
        assert source.source.fetcher == "fetchurl";
        prev.fetchurl source.source.args;

      # opencv-python is provided by opencv4 in nixpkgs (same cv2 module)
      pythonRemoveDeps = [ "opencv-python" ];

      dependencies = [
        mlx
        mlx-lm
        mlx-vlm
        mlx-embeddings
        transformers
        tokenizers
        huggingface-hub
        numpy
        pillow
        tqdm
        pyyaml
        gradioForVllm
        requests
        tabulate
        opencv4
        torchvision
        psutil
        fastapi
        uvicorn
        mcp
        jsonschema
        pytz
        prometheus-client
        lm-format-enforcer
      ];

      dontBuild = true;
      doCheck = false;

      pythonImportsCheck = [ "vllm_mlx" ];

      meta = {
        description = "vLLM-like inference for Apple Silicon via MLX";
        homepage = "https://github.com/vllm-mlx/vllm-mlx";
        license = lib.licenses.asl20;
        platforms = [ "aarch64-darwin" ];
        mainProgram = "vllm-mlx";
      };
    };

}
