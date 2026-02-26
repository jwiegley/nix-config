# overlays/30-vllm-mlx.nix
# Purpose: vLLM-like inference for Apple Silicon via MLX
# Dependencies: None (uses only prev)
# Packages: vllm-mlx
#
# NOTE: MLX requires Apple Metal GPU access and native dylibs that don't work
# in the Nix sandbox. This overlay installs vllm-mlx via uv into an isolated
# environment, then wraps the entry points for Nix.
_final: prev: {

  vllm-mlx =
    with prev;
    stdenv.mkDerivation rec {
      pname = "vllm-mlx";
      version = "0.2.6";

      dontUnpack = true;
      dontConfigure = true;
      dontBuild = true;

      nativeBuildInputs = [ makeWrapper ];

      installPhase = ''
        runHook preInstall
        mkdir -p $out/bin
        # Wrapper that ensures vllm-mlx is installed via uv on first run
        cat > $out/bin/vllm-mlx <<'WRAPPER'
        #!/usr/bin/env bash
        VLLM_MLX_HOME="''${XDG_DATA_HOME:-$HOME/.local/share}/vllm-mlx"
        if [ ! -d "$VLLM_MLX_HOME" ]; then
          echo "Installing vllm-mlx v${version} via uv..." >&2
          ${uv}/bin/uv tool install \
            "git+https://github.com/waybarrios/vllm-mlx.git" \
            --tool-dir "$VLLM_MLX_HOME" 2>&1 | tail -3 >&2
        fi
        exec "$VLLM_MLX_HOME/vllm-mlx/bin/vllm-mlx" "$@"
        WRAPPER
        chmod +x $out/bin/vllm-mlx
        runHook postInstall
      '';

      meta = {
        description = "vLLM-like inference for Apple Silicon via MLX";
        homepage = "https://github.com/waybarrios/vllm-mlx";
        license = lib.licenses.asl20;
        platforms = [ "aarch64-darwin" ];
        maintainers = with lib.maintainers; [ jwiegley ];
      };
    };

}
