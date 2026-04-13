# overlays/30-vllm-mlx.nix
# Purpose: vLLM-like inference for Apple Silicon via MLX
# Dependencies: Uses final for python3Packages (needs mlx, mlx-embeddings from extensions)
# Packages: vllm-mlx
final: prev: {

  vllm-mlx =
    with final;
    with final.python3Packages;
    buildPythonApplication rec {
      pname = "vllm-mlx";
      version = "0.2.8";
      pyproject = null;
      format = "wheel";

      src = prev.fetchurl {
        url = "https://files.pythonhosted.org/packages/54/e5/04730159e337b288e26b0957ee6a8e5647b47fb5e14f98e6d229565c1daf/vllm_mlx-${version}-py3-none-any.whl";
        hash = "sha256-RTmXt4qKx8d2XOXdL7/JrgEEkuUCGuif8Lb8RK9VK/I=";
      };

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
        gradio
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
      ];

      dontBuild = true;
      doCheck = false;

      pythonImportsCheck = [ "vllm_mlx" ];

      meta = {
        description = "vLLM-like inference for Apple Silicon via MLX";
        homepage = "https://github.com/vllm-mlx/vllm-mlx";
        license = lib.licenses.asl20;
        platforms = [ "aarch64-darwin" ];
        maintainers = with lib.maintainers; [ jwiegley ];
        mainProgram = "vllm-mlx";
      };
    };

}
