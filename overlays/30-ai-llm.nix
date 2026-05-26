# overlays/30-ai-llm.nix
# Purpose: Large Language Model inference tools
# Dependencies: Uses final for python3Packages in mlx-lm; uses prev elsewhere
# Packages: gguf-tools, hfdownloader, llama-cpp, llama-swap, mlx-lm, mtplx
final: prev: {

  # GGUF file manipulation tools
  gguf-tools =
    with prev;
    stdenv.mkDerivation rec {
      name = "gguf-tools-${version}";
      version = "fdfafbed";

      src = fetchFromGitHub {
        owner = "antirez";
        repo = "gguf-tools";
        rev = "fdfafbed766db0a1e9019b07994cd88f133d1aab";
        sha256 = "sha256-nkt/JbpeVb3AxSkDVhiwWfQF+r3orhzauq9T/y038CY=";
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
      version = "3.0.4";
      vendorHash = "sha256-DUALCwhuwQZ94uOVjw5wyY8z3fYr9WyDwVc89U34ytM=";

      src = fetchFromGitHub {
        owner = "bodaay";
        repo = "HuggingFaceModelDownloader";
        rev = "v${version}";
        hash = "sha256-5fwNajsj13YlWSz11uwS/LHasjgkNQJw4RbEFs4uLA0=";
      };

      meta = with lib; {
        description = "The HuggingFace Model Downloader is a utility tool for downloading models and datasets from the HuggingFace website";
        homepage = "https://github.com/bodaay/HuggingFaceModelDownloader";
        license = licenses.asl20;
        maintainers = [ maintainers.jwiegley ];
      };
    };

  # llama.cpp - LLM inference with GGUF models
  # NOTE: As of b9190+, the webui was relocated from tools/server/webui
  # to tools/ui. See nixpkgs commit dea49413 (llama-cpp: 9080 -> 9190).
  llama-cpp = prev.llama-cpp.overrideAttrs (attrs: rec {
    version = "9265";
    src = prev.fetchFromGitHub {
      owner = "ggml-org";
      repo = "llama.cpp";
      tag = "b${version}";
      hash = "sha256-aRabesT1N4owaUYQeIZwLeNnMzz08GoBIhRxODNYLFI=";
    };
    postPatch = "";
    npmRoot = "tools/ui";
    preConfigure = ''
      prependToVar cmakeFlags "-DLLAMA_BUILD_COMMIT:STRING=b${version}"
      pushd tools/ui
      # node 24.15.0's libuv has a kqueue assertion bug that triggers
      # SIGABRT on exit (`Assertion failed: (errno == EINTR), function
      # uv__io_poll, file kqueue.c, line 279`). The build artifacts under
      # build/tools/ui/dist/ are written before the abort, so accept the
      # non-zero exit only when the expected output actually exists.
      npm run build || true
      [[ -f ../../build/tools/ui/dist/index.html ]] || {
        echo "ERROR: tools/ui/dist/index.html not produced — npm run build genuinely failed" >&2
        exit 1
      }
      popd
    '';
    npmDepsHash = "sha256-Iyg8FpcTKf2UYHuK7mA3cTAqVaLcQPcS0YCa5Qf01Gc=";
    npmDeps = prev.fetchNpmDeps {
      name = "llama-cpp-${version}-npm-deps";
      inherit src;
      inherit (attrs) patches;
      preBuild = "pushd tools/ui";
      hash = npmDepsHash;
    };
  });

  # llama-swap - Model swapping for llama.cpp
  llama-swap =
    let
      version = "216";

      src = prev.fetchFromGitHub {
        owner = "mostlygeek";
        repo = "llama-swap";
        rev = "v${version}";
        hash = "sha256-FuGy+5Ziu4zIheiYzH9GwbkKXzMibR0VlagTNTcSp4A=";
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

          npmDepsHash = "sha256-NJqEJ+XTdpPFtJJxP4CGu+JDUW7lKDcFgsixQJ3SXtQ=";

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
      vendorHash = "sha256-QysQ7YdwJcLTziwL25j73n3tQVvzVQIFxN4GkTU8JZg=";
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
  pythonPackagesExtensions = (prev.pythonPackagesExtensions or [ ]) ++ [
    (_: pprev: {
      pyarrow = pprev.pyarrow.overrideAttrs (_: {
        doCheck = false;
        doInstallCheck = false;
      });
    })
  ];

  # guidellm - LLM deployment benchmarking tool
  guidellm =
    with final;
    with final.python3Packages;
    buildPythonApplication rec {
      pname = "guidellm";
      version = "0.5.3";
      pyproject = null;
      format = "wheel";

      src = fetchPypi {
        inherit pname version;
        format = "wheel";
        dist = "py3";
        python = "py3";
        hash = "sha256-yoS5xDPeDIu4Qn6BjM9FMypLt/IBgwjrs669WVYVNXo=";
      };

      dependencies = [
        click
        culsans
        datasets
        eval-type-backport
        faker
        ftfy
        httpx
        h2 # httpx[http2] support required by guidellm
        loguru
        msgpack
        numpy
        protobuf
        pydantic
        pydantic-settings
        pyyaml
        rich
        sanic
        tabulate
        transformers
        uvloop
        torch
        more-itertools
        # recommended extras
        orjson
        msgspec
      ];

      dontBuild = true;
      doCheck = false; # Tests require running LLM servers

      pythonImportsCheck = [ "guidellm" ];

      meta = {
        description = "Benchmarking tool for evaluating LLM deployments";
        homepage = "https://github.com/vllm-project/guidellm";
        license = lib.licenses.asl20;
        maintainers = with lib.maintainers; [ jwiegley ];
        mainProgram = "guidellm";
      };
    };

  # mlx-lm - Apple MLX-based LLM inference
  # NOTE: Using 'final' here because mlx-lm needs final python3Packages
  # which may include our pythonPackagesExtensions modifications
  mlx-lm =
    with final;
    with final.python3Packages;
    buildPythonApplication rec {
      pname = "mlx-lm";
      version = "0.31.3";
      pyproject = true;

      src = fetchFromGitHub {
        owner = "ml-explore";
        repo = "mlx-lm";
        tag = "v${version}";
        hash = "sha256-DPOJfsIucG8mWt4ZKenymCJo/i9Jw+a+iuIygIIYkA8=";
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

  # mtplx - MTP speculative decoding runtime for Apple Silicon (MLX-native)
  # Built as buildPythonPackage + python.withPackages (rather than
  # buildPythonApplication) because mtplx spawns its server via
  # `os.execvpe(sys.executable, ["-m", "mtplx.server.openai", ...])`
  # (see mtplx/commands/public.py). buildPythonApplication's wrapper
  # uses site.addsitedir at runtime — that mutates sys.path of the
  # current interpreter only and does not propagate to subprocesses,
  # so the spawned python cannot import mtplx. python.withPackages
  # installs mtplx as a real site-package in the env, so subprocesses
  # using sys.executable resolve mtplx via NIX_PYTHONPATH.
  mtplx =
    let
      pyPkg =
        with final;
        with final.python3Packages;
        buildPythonPackage rec {
          pname = "mtplx";
          version = "0.3.7";
          pyproject = null;
          format = "wheel";

          src = fetchPypi {
            inherit pname version;
            format = "wheel";
            dist = "py3";
            python = "py3";
            hash = "sha256-246JJhnR6ssBr1qPetgFXrjoMLW3BwR+Ud+f3c6LMzY=";
          };

          # nixpkgs ships slightly older fastapi (0.128) and uvicorn (0.40);
          # mtplx pins >=0.136 / >=0.46 but works fine with these versions.
          # pythonRelaxDeps doesn't rewrite wheel METADATA, so skip the check.
          dontCheckRuntimeDeps = true;

          propagatedBuildInputs = [
            fastapi
            huggingface-hub
            mlx
            mlx-lm
            nanobind
            numpy
            pydantic
            rich
            safetensors
            uvicorn
          ];

          dontBuild = true;
          doCheck = false;

          pythonImportsCheck = [ "mtplx" ];
        };

      pyEnv = final.python3.withPackages (_: [ pyPkg ]);
    in
    final.runCommand "mtplx-${pyPkg.version}"
      {
        inherit (pyPkg) version;
        meta = {
          description = "MTP speculative decoding runtime for Apple Silicon (MLX-native)";
          homepage = "https://github.com/youssofal/MTPLX";
          license = final.lib.licenses.asl20;
          platforms = [ "aarch64-darwin" ];
          maintainers = with final.lib.maintainers; [ jwiegley ];
          mainProgram = "mtplx";
        };
      }
      ''
        mkdir -p $out/bin
        ln -s ${pyEnv}/bin/mtplx $out/bin/mtplx
        ln -s ${pyEnv}/bin/mtplx-tune $out/bin/mtplx-tune
      '';

  # omlx - LLM inference server optimized for Apple Silicon
  # NOTE: Using 'final' so deps resolve against our extended python3Packages
  # (mlx wheel override, mlx-embeddings, dflash-mlx). omlx is pure Python;
  # the Homebrew formula's Rust dependency was only for transitive wheels
  # (pydantic-core, tiktoken) which nixpkgs supplies prebuilt.
  omlx =
    with final;
    with final.python3Packages;
    buildPythonApplication rec {
      pname = "omlx";
      version = "0.3.11";
      pyproject = true;

      src = fetchFromGitHub {
        owner = "jundot";
        repo = "omlx";
        tag = "v${version}";
        hash = "sha256-HulLMgByshCmxn9+/Eg+BNabOa8zq/OkQigmoHllc48=";
      };

      # pyproject.toml pins mlx-lm/mlx-embeddings/mlx-vlm/dflash-mlx to git
      # commits via PEP 508 direct references, which fail in the Nix sandbox.
      # Strip the URLs (targeted replacements so an upstream format change
      # surfaces as a build error rather than a silent dependency mismatch)
      # so resolution lands on our overlay/nixpkgs versions.
      postPatch = ''
        substituteInPlace pyproject.toml \
          --replace-fail '"mlx-lm @ git+https://github.com/ml-explore/mlx-lm@ed1fca4cef15a824c5f1702c80f70b4cffc8e4dd"' '"mlx-lm"' \
          --replace-fail '"mlx-embeddings @ git+https://github.com/Blaizzy/mlx-embeddings@32981fa4e8064ed664b52071789dd18271fe4206"' '"mlx-embeddings"' \
          --replace-fail '"mlx-vlm @ git+https://github.com/Blaizzy/mlx-vlm@f96138eef1f5ce7fb5d97f8dd41a664a195b5659"' '"mlx-vlm"' \
          --replace-fail '"dflash-mlx @ git+https://github.com/bstnxbt/dflash-mlx@1ba671372b289c025b435c1a13aabb4bfb80b183"' '"dflash-mlx"'
      '';

      build-system = [
        setuptools
        wheel
      ];

      dependencies = [
        mlx
        mlx-lm
        mlx-embeddings
        mlx-vlm
        dflash-mlx
        regex
        transformers
        mistral-common
        tokenizers
        huggingface-hub
        numpy
        tqdm
        pyyaml
        itsdangerous
        jinja2
        sentencepiece
        tiktoken
        protobuf
        requests
        socksio
        tabulate
        psutil
        fastapi
        uvicorn
        python-multipart
        jsonschema
        openai-harmony
        pillow
      ];

      doCheck = false;
      pythonImportsCheck = [ "omlx" ];

      # Smoke test that the wrapped entry point runs. omlx's CLI uses
      # subcommands (serve/launch/diagnose) and has no --version flag, so
      # exercise --help, which builds the full argparse tree and exits 0.
      doInstallCheck = true;
      installCheckPhase = ''
        runHook preInstallCheck
        $out/bin/omlx --help > /dev/null
        runHook postInstallCheck
      '';

      meta = {
        description = "LLM inference server optimized for Apple Silicon";
        homepage = "https://github.com/jundot/omlx";
        license = lib.licenses.asl20;
        platforms = [ "aarch64-darwin" ];
        mainProgram = "omlx";
        maintainers = with lib.maintainers; [ jwiegley ];
      };
    };

}
