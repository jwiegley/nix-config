# overlays/30-vllm-mlx.nix
# Purpose: vLLM-like inference for Apple Silicon via MLX
# Dependencies: None (uses only prev)
# Packages: vllm-mlx
#
# NOTE: MLX requires Apple Metal GPU access and native dylibs that don't work
# in the Nix sandbox. This overlay installs vllm-mlx via uv on first run.
_final: prev: {

  vllm-mlx =
    with prev;
    stdenv.mkDerivation rec {
      pname = "vllm-mlx";
      version = "0.2.6";

      dontUnpack = true;
      dontConfigure = true;
      dontBuild = true;

      installPhase = ''
        runHook preInstall
        mkdir -p $out/bin

        cat > $out/bin/vllm-mlx <<EOF
#!/usr/bin/env bash
UV="${uv}/bin/uv"
TOOL_DIR="\''${XDG_DATA_HOME:-\$HOME/.local/share}/uv/tools"

if [ ! -d "\$TOOL_DIR/vllm-mlx" ]; then
  echo "Installing vllm-mlx v${version} via uv..." >&2
  "\$UV" tool install "vllm-mlx==${version}" >&2
fi

exec "\$UV" tool run vllm-mlx "\$@"
EOF
        chmod +x $out/bin/vllm-mlx

        cat > $out/bin/vllm-mlx-chat <<EOF
#!/usr/bin/env bash
UV="${uv}/bin/uv"
TOOL_DIR="\''${XDG_DATA_HOME:-\$HOME/.local/share}/uv/tools"

if [ ! -d "\$TOOL_DIR/vllm-mlx" ]; then
  echo "Installing vllm-mlx v${version} via uv..." >&2
  "\$UV" tool install "vllm-mlx==${version}" >&2
fi

exec "\$UV" tool run vllm-mlx-chat "\$@"
EOF
        chmod +x $out/bin/vllm-mlx-chat

        cat > $out/bin/vllm-mlx-bench <<EOF
#!/usr/bin/env bash
UV="${uv}/bin/uv"
TOOL_DIR="\''${XDG_DATA_HOME:-\$HOME/.local/share}/uv/tools"

if [ ! -d "\$TOOL_DIR/vllm-mlx" ]; then
  echo "Installing vllm-mlx v${version} via uv..." >&2
  "\$UV" tool install "vllm-mlx==${version}" >&2
fi

exec "\$UV" tool run vllm-mlx-bench "\$@"
EOF
        chmod +x $out/bin/vllm-mlx-bench

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
