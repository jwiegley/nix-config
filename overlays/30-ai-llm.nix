# overlays/30-ai-llm.nix
# Purpose: Large Language Model inference tools
# Dependencies: Uses final for python3Packages in mlx-lm; uses prev elsewhere
# Packages: gguf-tools, hfdownloader, llama-cpp, llama-swap, mlx-lm
final: prev: {

  # GGUF file manipulation tools
  gguf-tools =
    with prev;
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
        description = "This is a work in progress library to manipulate GGUF files";
        license = lib.licenses.mit;
        maintainers = with lib.maintainers; [ jwiegley ];
      };
    };

  # HuggingFace model downloader
  hfdownloader =
    with prev;
    buildGoModule rec {
      pname = "hfdownloader";
      version = "3.0.3";
      vendorHash = "sha256-DUALCwhuwQZ94uOVjw5wyY8z3fYr9WyDwVc89U34ytM=";

      src = fetchFromGitHub {
        owner = "bodaay";
        repo = "HuggingFaceModelDownloader";
        rev = "v${version}";
        hash = "sha256-QpDtUAzR0sPKL/EwS5IhjtgE1bDj4ompAYMvK8kEOQs=";
      };

      meta = with lib; {
        description = "The HuggingFace Model Downloader is a utility tool for downloading models and datasets from the HuggingFace website";
        homepage = "https://github.com/bodaay/HuggingFaceModelDownloader";
        license = licenses.asl20;
        maintainers = [ maintainers.jwiegley ];
      };
    };

  # llama.cpp - LLM inference with GGUF models
  llama-cpp = prev.llama-cpp.overrideAttrs (attrs: rec {
    version = "8164";
    src = prev.fetchFromGitHub {
      owner = "ggml-org";
      repo = "llama.cpp";
      tag = "b${version}";
      hash = "sha256-aAiqLNVdyYWihUV5zSyua80gq84OkjE4Fa2j8PxpsSQ=";
    };
    npmDepsHash = "sha256-FKjoZTKm0ddoVdpxzYrRUmTiuafEfbKc4UD2fz2fb8A=";
    npmDeps = prev.fetchNpmDeps {
      name = "llama-cpp-${version}-npm-deps";
      inherit src;
      inherit (attrs) patches;
      preBuild = "pushd tools/server/webui";
      hash = npmDepsHash;
    };
  });

  # llama-swap - Model swapping for llama.cpp
  llama-swap =
    let
      version = "195";

      src = prev.fetchFromGitHub {
        owner = "mostlygeek";
        repo = "llama-swap";
        rev = "v${version}";
        hash = "sha256-Fc6aZDVhI8dvJUzZOn6iLqxmYht0GuXI8VjOQmln/2M=";
      };

      ui =
        with prev;
        buildNpmPackage (finalAttrs: {
          pname = "llama-swap-ui";
          inherit version src;

          postPatch = ''
            substituteInPlace vite.config.ts \
            --replace '../proxy/ui_dist' '${placeholder "out"}/ui_dist'
          '';

          sourceRoot = "source/ui-svelte";

          npmDepsHash = "sha256-4VH9jJ1Ae16p8kUubZBrIwwqw/X8I+wDg378G82WCtU=";

          postInstall = ''
            rm -rf $out/lib
          '';

          meta = {
            description = "llama-swap - UI";
            license = lib.licenses.mit;
            platforms = lib.platforms.unix;
          };
        });
    in
    with prev;
    prev.llama-swap.overrideAttrs (attrs: rec {
      inherit version src;
      # vendorHash = "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=";
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
        description = "Model swapping for llama.cpp (or any local OpenAPI compatible server)";
        license = lib.licenses.mit;
        platforms = lib.platforms.unix;
        mainProgram = "llama-swap";
      };
    });

  # pyarrow 22.0.0 has a broken test (test_timezone_absent) in the Nix sandbox
  # that causes cascade failures for datasets, tokenizers, transformers, mlx-lm
  pythonPackagesExtensions = prev.pythonPackagesExtensions ++ [
    (_: pprev: {
      pyarrow = pprev.pyarrow.overrideAttrs (_: {
        doCheck = false;
        doInstallCheck = false;
      });
    })
  ];

  # mlx-lm - Apple MLX-based LLM inference
  # NOTE: Using 'final' here because mlx-lm needs final python3Packages
  # which may include our pythonPackagesExtensions modifications
  mlx-lm =
    with final;
    with final.python3Packages;
    buildPythonApplication rec {
      pname = "mlx-lm";
      version = "0.30.7";
      pyproject = true;

      src = fetchFromGitHub {
        owner = "ml-explore";
        repo = "mlx-lm";
        tag = "v${version}";
        hash = "sha256-Jc+JyReOH8Wja8sh9BvOO6X090xutKrVSbv+lEODPls=";
      };

      build-system = [ setuptools ];
      dependencies = [
        mlx
        transformers
        protobuf
        jinja2
      ];

      doCheck = false; # Tests require additional dependencies

      meta = {
        description = "LLM access to models using MLX";
        homepage = "https://github.com/mlx-explore/mlx-lm";
        license = lib.licenses.mit;
        maintainers = with lib.maintainers; [ jwiegley ];
      };
    };

}
