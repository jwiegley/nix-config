# overlays/30-ai-llm.nix
# Purpose: Large Language Model inference tools
# Dependencies: Uses final for python3Packages in mlx-lm; uses prev elsewhere
# Packages: gguf-tools, hfdownloader, llama-cpp, llama-swap, mlx-lm
final: prev: {

  # GGUF file manipulation tools
  gguf-tools = with prev;
    stdenv.mkDerivation rec {
      name = "gguf-tools-${version}";
      version = "a3257ff3";

      src = fetchFromGitHub {
        owner = "antirez";
        repo = "gguf-tools";
        rev = "a3257ff3cb8aed8b60ba3243c70b85a17491d7d6";
        sha256 = "1dgm1l194blgcbg1ma1lmzprydfgbbkv5bvp1mpdg6ysc2g6i8d4";
        # date = 2025-08-28T16:35:01+02:00;
      };

      installPhase = ''
        mkdir -p $out/bin
        cp -p gguf-tools $out/bin
      '';

      meta = {
        homepage = "https://github.com/antirez/gguf-tools";
        description =
          "This is a work in progress library to manipulate GGUF files";
        license = lib.licenses.mit;
        maintainers = with lib.maintainers; [ jwiegley ];
      };
    };

  # HuggingFace model downloader
  hfdownloader = with prev;
    buildGoModule rec {
      pname = "hfdownloader";
      version = "2.3.3";
      vendorHash = "sha256-xswTwm37YakOobXl8A1S/3wzvAC5U2j2j/xN2m9tJ2s=";

      src = fetchFromGitHub {
        owner = "bodaay";
        repo = "HuggingFaceModelDownloader";
        rev = "${version}";
        hash = "sha256-2Y5jwXrTJKcMOus0zLXLhCVK5Q7CH4lydhMVa0EEFWI=";
      };

      meta = with lib; {
        description =
          "The HuggingFace Model Downloader is a utility tool for downloading models and datasets from the HuggingFace website";
        homepage = "https://github.com/bodaay/HuggingFaceModelDownloader";
        license = licenses.asl20;
        maintainers = [ maintainers.jwiegley ];
      };
    };

  # llama.cpp - LLM inference with GGUF models
  llama-cpp = prev.llama-cpp.overrideAttrs (attrs: rec {
    version = "7679";
    src = prev.fetchFromGitHub {
      owner = "ggml-org";
      repo = "llama.cpp";
      tag = "b${version}";
      hash = "sha256-aU981UeCpdStxYMRJNOuTzfgIpLtnxnQeYsh/EH7c2c=";
    };
    # Fix macOS dylib version: 0.0.7236 exceeds max patch version (255)
    cmakeFlags = (attrs.cmakeFlags or [ ])
      ++ prev.lib.optionals prev.stdenv.hostPlatform.isDarwin
      [ "-DLLAMA_BUILD_NUMBER=0" ];
  });

  # llama-swap - Model swapping for llama.cpp
  llama-swap = let
    version = "182";

    src = prev.fetchFromGitHub {
      owner = "mostlygeek";
      repo = "llama-swap";
      rev = "v${version}";
      hash = "sha256-1uvrKFj5816PPWiDnzGBw/kdgt3rShHp2IyuBCunf64=";
    };

    ui = with prev;
      buildNpmPackage (finalAttrs: {
        pname = "llama-swap-ui";
        inherit version src;

        postPatch = ''
          substituteInPlace vite.config.ts \
          --replace '../proxy/ui_dist' '${placeholder "out"}/ui_dist'
        '';

        sourceRoot = "source/ui";

        npmDepsHash = "sha256-RKPcMwJ0qVOgbTxoGryrLn7AW0Bfmv9WasoY+gw4B30=";

        postInstall = ''
          rm -rf $out/lib
        '';

        meta = {
          description = "llama-swap - UI";
          license = lib.licenses.mit;
          platforms = lib.platforms.unix;
        };
      });
  in with prev;
  prev.llama-swap.overrideAttrs (attrs: rec {
    inherit version src;
    vendorHash = "sha256-XiDYlw/byu8CWvg4KSPC7m8PGCZXtp08Y1velx4BR8U=";
    preBuild = ''
      cp -r ${ui}/ui_dist proxy/
    '';
    ldflags = [
      "-X main.version=${version}"
      "-X main.date=unknown"
      "-X main.commit=v${version}"
    ];
    doCheck = false;
    meta = {
      description =
        "Model swapping for llama.cpp (or any local OpenAPI compatible server)";
      license = lib.licenses.mit;
      platforms = lib.platforms.unix;
      mainProgram = "llama-swap";
    };
  });

  # mlx-lm - Apple MLX-based LLM inference
  # NOTE: Using 'final' here because mlx-lm needs final python3Packages
  # which may include our pythonPackagesExtensions modifications
  mlx-lm = with final;
    with final.python3Packages;
    buildPythonApplication rec {
      pname = "mlx-lm";
      version = "0.30.2";
      pyproject = true;

      src = fetchFromGitHub {
        owner = "ml-explore";
        repo = "mlx-lm";
        tag = "v${version}";
        hash = "sha256-6WlKAchze5B724XYwzpVHy+17HlMcGSYjJw0aOdm5yw=";
      };

      build-system = [ setuptools ];
      dependencies = [ mlx transformers protobuf jinja2 ];

      doCheck = false; # Tests require additional dependencies

      meta = {
        description = "LLM access to models using MLX";
        homepage = "https://github.com/mlx-explore/mlx-lm";
        license = lib.licenses.mit;
        maintainers = with lib.maintainers; [ jwiegley ];
      };
    };

}
