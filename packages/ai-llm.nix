# Independent LLM application packages.
{ final, prev }:

let
  sources = import ./source-catalog.nix "ai";
in
{
  # GGUF file manipulation tools
  gguf-tools =
    with prev;
    stdenv.mkDerivation rec {
      name = "gguf-tools-${version}";
      version = sources.gguf-tools.version;

      src =
        assert sources.gguf-tools.source.fetcher == "fetchFromGitHub";
        fetchFromGitHub sources.gguf-tools.source.args;

      installPhase = ''
        mkdir -p $out/bin
        cp -p gguf-tools $out/bin
      '';

      meta = {
        homepage = "https://github.com/antirez/gguf-tools";
        description = "This is a work in progress library to manipulate GGUF files";
        license = lib.licenses.mit;
      };
    };

  # HuggingFace model downloader
  hfdownloader =
    with prev;
    buildGoModule rec {
      pname = "hfdownloader";
      version = sources.hfdownloader.version;
      vendorHash = sources.hfdownloader.hashes.vendorHash;
      doCheck = false; # Upstream has timing-sensitive server cancellation tests.

      src =
        assert sources.hfdownloader.source.fetcher == "fetchFromGitHub";
        fetchFromGitHub sources.hfdownloader.source.args;

      meta = with lib; {
        description = "The HuggingFace Model Downloader is a utility tool for downloading models and datasets from the HuggingFace website";
        homepage = "https://github.com/bodaay/HuggingFaceModelDownloader";
        license = licenses.asl20;
      };
    };

  # llama-swap - Model swapping for llama.cpp
  llama-swap =
    let
      version = sources.llama-swap.version;

      src =
        assert sources.llama-swap.source.fetcher == "fetchFromGitHub";
        prev.fetchFromGitHub sources.llama-swap.source.args;

      ui =
        with prev;
        buildNpmPackage (_finalAttrs: {
          pname = "llama-swap-ui";
          inherit version src;

          # Redirect Vite's in-tree output to this derivation's writable output.
          # --replace-fail makes an upstream layout change fail explicitly.
          postPatch = ''
            substituteInPlace vite.config.ts \
            --replace-fail '"../internal/server/ui_dist"' '"${placeholder "out"}/ui_dist"'
          '';

          sourceRoot = "source/ui";

          npmDepsHash = sources.llama-swap.hashes.npmDepsHash;

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
    prev.llama-swap.overrideAttrs (_attrs: rec {
      inherit version src;
      vendorHash = sources.llama-swap.hashes.vendorHash;
      preBuild = ''
        # The main binary embeds internal/server/ui_dist, which the source
        # archive omits; populate it with the built Vite output.
        rm -rf internal/server/ui_dist
        cp -r ${ui}/ui_dist internal/server/
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

  # AIPerf - Generative AI model-server benchmarking
  aiperf =
    let
      # AIPerf 0.12.0 requires Python >=3.11,<3.14. nixpkgs' default Python is
      # 3.14, so keep this application and its private dependencies on 3.13.
      ps = prev.python313Packages;

      crick = ps.buildPythonPackage rec {
        pname = "crick";
        inherit (sources.crick) version;
        pyproject = true;

        src =
          assert sources.crick.source.fetcher == "fetchPypi";
          ps.fetchPypi sources.crick.source.args;

        build-system = [
          ps.setuptools
          ps.setuptools-scm
          ps.cython
          ps.numpy
          ps.versioneer
        ];

        dependencies = [ ps.numpy ];

        # Retain the installed-module and TDigest checks below.
        doCheck = false;
        pythonImportsCheck = [ "crick" ];

        meta = {
          description = "High-performance approximate and streaming algorithms";
          homepage = "https://github.com/dask/crick";
          license = prev.lib.licenses.bsd3;
        };
      };

      choreographer = ps.buildPythonPackage {
        pname = "choreographer";
        inherit (sources.choreographer) version;
        format = "wheel";

        src =
          assert sources.choreographer.source.fetcher == "fetchurl";
          prev.fetchurl sources.choreographer.source.args;

        dependencies = [
          ps.logistro
          ps.platformdirs
          ps.simplejson
        ];

        doCheck = false;
        pythonImportsCheck = [ "choreographer" ];

        meta = {
          description = "DevTools Protocol implementation for Chrome";
          homepage = "https://github.com/plotly/choreographer";
          license = prev.lib.licenses.mit;
        };
      };

      # AIPerf 0.12.0 declares kaleido~=1.2.0. Keep the catalog target manual
      # until AIPerf accepts the 1.3 series.
      kaleido = ps.buildPythonPackage rec {
        pname = "kaleido";
        inherit (sources.kaleido) version;
        format = "wheel";

        src =
          assert sources.kaleido.source.fetcher == "fetchurl";
          prev.fetchurl sources.kaleido.source.args;

        dependencies = [
          choreographer
          ps.logistro
          ps.orjson
          ps.packaging
          ps.pytest-timeout
        ];

        # Retain the import check and AIPerf plugin validation below.
        doCheck = false;
        pythonImportsCheck = [ "kaleido" ];

        meta = {
          description = "Static image export for web-based visualization libraries";
          homepage = "https://github.com/plotly/Kaleido";
          license = prev.lib.licenses.mit;
        };
      };

      # Exclude Zsh completion coverage from the Darwin matrix; other shell tests
      # remain except the separately disabled whitespace-choice case.
      aiperfCyclopts =
        if prev.stdenv.hostPlatform.isDarwin then
          ps.cyclopts.overridePythonAttrs (old: {
            postPatch = (old.postPatch or "") + ''
              substituteInPlace tests/completion/test_behavior.py \
                --replace-fail 'params=["bash", "zsh", "fish"]' \
                'params=["bash", "fish"]'
            '';
            # A renamed path fails loudly instead of silently changing coverage.
            disabledTestPaths = (old.disabledTestPaths or [ ]) ++ [
              "tests/completion/test_zsh.py"
            ];
            disabledTests = (old.disabledTests or [ ]) ++ [
              "test_choice_with_whitespace"
            ];
          })
        else
          ps.cyclopts;
    in
    ps.buildPythonApplication rec {
      pname = "aiperf";
      inherit (sources.aiperf) version;
      format = "wheel";

      src =
        assert sources.aiperf.source.fetcher == "fetchurl";
        prev.fetchurl sources.aiperf.source.args;

      dependencies =
        (with ps; [
          aiofiles
          aiohttp
          dash
          dash-bootstrap-components
          datasets
          fastapi
          ffmpeg-python
          huggingface-hub
          jinja2
          jmespath
          matplotlib
          msgspec
          numpy
          nvidia-ml-py
          optuna
          orjson
          pandas
          pillow
          plotly
          prometheus-client
          protobuf
          psutil
          pyarrow
          pydantic
          pydantic-settings
          pyzmq
          rich
          ruamel-yaml
          scipy
          sentencepiece
          setproctitle
          soundfile
          starlette-compress
          textual
          tiktoken
          tqdm
          transformers
          uvicorn
          uvloop
          zstandard
        ])
        ++ ps.uvicorn.optional-dependencies.standard
        ++ [
          crick
          aiperfCyclopts
          kaleido
          ps.seaborn
        ];

      # Relax only these runtime constraints; all others remain checked.
      pythonRelaxDeps = [
        "aiofiles"
        "aiohttp"
        "dash"
        "jmespath"
        "pandas"
        "pillow"
        "plotly"
        "prometheus-client"
        "psutil"
        "pyzmq"
        "rich"
        "ruamel-yaml"
        "textual"
      ];

      # ffmpeg-python is only the graph builder. AIPerf checks for the real
      # executable before synthesizing video inputs.
      nativeBuildInputs = [ prev.makeWrapper ];
      makeWrapperArgs = [
        "--prefix PATH : ${prev.lib.makeBinPath [ prev.ffmpeg-headless ]}"
      ];

      # Exercise the installed CLI and packaged resources in installCheckPhase.
      pythonImportsCheck = [
        "aiperf"
        "aiperf.cli"
      ];

      installCheckPhase = ''
        export HOME="$TMPDIR/home"
        export XDG_CACHE_HOME="$HOME/.cache"
        export HF_HUB_OFFLINE=1
        export TRANSFORMERS_OFFLINE=1
        export COLUMNS=120
        mkdir -p "$HOME" "$XDG_CACHE_HOME"

        ${ps.python.withPackages (_: [ crick ])}/bin/python - <<'PY'
        from crick import TDigest

        digest = TDigest()
        digest.update([1.0, 2.0, 3.0])
        assert digest.quantile(0.5) == 2.0
        PY

        version="$($out/bin/aiperf --version)"
        test "$version" = "${version}"

        $out/bin/aiperf --help > "$TMPDIR/help.txt"
        grep -F "NVIDIA AIPerf v${version}" "$TMPDIR/help.txt"
        grep -F "Installed Plugin Packages: aiperf (v${version})" "$TMPDIR/help.txt"

        $out/bin/aiperf plugins --all --validate > "$TMPDIR/plugins.txt"
        grep -F "All checks passed" "$TMPDIR/plugins.txt"

        $out/bin/aiperf profile --help > "$TMPDIR/profile-help.txt"
        grep -F "Benchmark generative AI models" "$TMPDIR/profile-help.txt"

        $out/bin/aiperf config init --list > /dev/null
        $out/bin/aiperf config init --template minimal \
          --output "$TMPDIR/minimal.yaml"
        $out/bin/aiperf config validate "$TMPDIR/minimal.yaml"
      '';

      meta = {
        description = "Performance testing for generative AI model servers";
        homepage = "https://github.com/ai-dynamo/aiperf";
        license = prev.lib.licenses.asl20;
        mainProgram = "aiperf";
        platforms = [
          "aarch64-darwin"
          "aarch64-linux"
          "x86_64-linux"
        ];
      };
    };

  # guidellm - LLM deployment benchmarking tool
  guidellm =
    with final;
    with final.python3Packages;
    buildPythonApplication rec {
      pname = "guidellm";
      inherit (sources.guidellm) version;
      pyproject = null;
      format = "wheel";

      src =
        assert sources.guidellm.source.fetcher == "fetchPypi";
        fetchPypi sources.guidellm.source.args;

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
        orjson
        msgspec
      ];

      dontBuild = true;
      doCheck = false; # Upstream tests require running LLM servers.

      pythonImportsCheck = [ "guidellm" ];

      meta = {
        description = "Benchmarking tool for evaluating LLM deployments";
        homepage = "https://github.com/vllm-project/guidellm";
        license = lib.licenses.asl20;
        mainProgram = "guidellm";
      };
    };

  # Install mtplx in a Python environment so subprocesses launched through
  # sys.executable resolve the package.
  mtplx =
    let
      pyPkg =
        with final;
        with final.python3Packages;
        buildPythonPackage rec {
          pname = "mtplx";
          inherit (sources.mtplx) version;
          pyproject = true;

          src =
            assert sources.mtplx.source.fetcher == "fetchPypi";
            fetchPypi sources.mtplx.source.args;

          # MTPLX 2.8.3 still needs the pending Transformers 5.15
          # compatibility backport.
          # https://github.com/youssofal/MTPLX/pull/260
          patches = [ ../overlays/ai/patches/mtplx-transformers-5.15.patch ];

          build-system = [
            setuptools
            wheel
          ];

          nativeCheckInputs = [ packaging ];

          propagatedBuildInputs = [
            fastapi
            huggingface-hub
            pillow
            mlx
            mlx-lm
            nanobind
            numpy
            pydantic
            rich
            safetensors
            transformers
            uvicorn
          ];

          # Upstream's model-download and live-server integration suite is not
          # a deterministic package-build contract. Verify the rebuilt wheel's
          # installed dependency semantics against this package set instead.
          # buildPythonPackage maps doCheck to doInstallCheck, so this enables
          # the custom installCheckPhase below (not an upstream checkPhase).
          doCheck = true;
          installCheckPhase = ''
            runHook preInstallCheck
            (
              cd "$out"
              PYTHONPATH="$out/${python.sitePackages}:''${PYTHONPATH:-}" \
                ${python.interpreter} - <<'PY'
            from importlib import metadata

            from packaging.requirements import Requirement
            from packaging.version import Version
            import transformers

            requirements = [
                Requirement(value)
                for value in metadata.requires("mtplx") or ()
                if Requirement(value).name == "transformers"
            ]
            assert len(requirements) == 1, requirements
            requirement = requirements[0]
            assert Version("5.13.0") not in requirement.specifier, requirement
            assert Version("5.14.1") in requirement.specifier, requirement
            assert Version("5.15.0") in requirement.specifier, requirement
            assert Version("5.15.999") in requirement.specifier, requirement
            assert Version("5.16.0") not in requirement.specifier, requirement
            assert str(requirement.marker) == (
                'sys_platform == "darwin" and platform_machine == "arm64"'
            ), requirement

            selected = Version(transformers.__version__)
            assert selected.release[:2] == (5, 15), selected
            assert selected in requirement.specifier, (selected, requirement)
            PY
            )
            runHook postInstallCheck
          '';

          pythonImportsCheck = [ "mtplx" ];
        };

      pyEnv = final.python3.withPackages (_: [ pyPkg ]);
    in
    final.runCommand "mtplx-${pyPkg.version}"
      {
        inherit (pyPkg) version;
        passthru.tests.transformers-compat = pyPkg;
        meta = {
          description = "MTP speculative decoding runtime for Apple Silicon (MLX-native)";
          homepage = "https://github.com/youssofal/MTPLX";
          license = final.lib.licenses.asl20;
          platforms = [ "aarch64-darwin" ];
          mainProgram = "mtplx";
        };
      }
      ''
        mkdir -p $out/bin
        ln -s ${pyEnv}/bin/mtplx $out/bin/mtplx
        ln -s ${pyEnv}/bin/mtplx-tune $out/bin/mtplx-tune
      '';

  # Build omlx on Python 3.13 with the extended MLX package set.
  omlx =
    with final;
    with final.python313Packages;
    buildPythonApplication rec {
      pname = "omlx";
      version = sources.omlx.version;
      pyproject = true;

      src =
        assert sources.omlx.source.fetcher == "fetchFromGitHub";
        fetchFromGitHub sources.omlx.source.args;

      patches = [ ../overlays/ai/patches/omlx-host-vm-info64-count.patch ];

      # pyproject.toml pins mlx-lm/mlx-embeddings/mlx-vlm/dflash-mlx to git
      # commits via PEP 508 direct references, which fail in the Nix sandbox.
      # Strip the URLs (targeted replacements so an upstream format change
      # surfaces as a build error rather than a silent dependency mismatch)
      # so resolution lands on our overlay/nixpkgs versions.
      #
      # cmake and nanobind build only optional custom Metal kernels, which are
      # disabled because the sandbox lacks that toolchain. Drop those two build
      # requirements; the remaining MLX requirement is supplied by our wheel.
      # This build ships no ABI-coupled custom kernels, so retarget upstream's
      # three exact MLX pins to the selected 0.32.1 wheel.
      postPatch = ''
        substituteInPlace pyproject.toml \
          --replace-fail '"mlx==0.32.0"' '"mlx==0.32.1"'
        substituteInPlace pyproject.toml \
          --replace-fail '"ddgs==9.14.4"' '"ddgs==${ddgs.version}"' \
          --replace-fail '    # DuckDuckGo backend for the chat web_search tool. Pinned to 9.14.1:' '    # DDGS backend for the chat web_search tool, pinned by the package set:' \
          --replace-fail "    # the last release inside packaging/venvstacks.toml's exclude-newer" "" \
          --replace-fail '    # cutoff (2026-04-23), and the last with the minimal dep tree' "" \
          --replace-fail '    # (click/primp/lxml only; 9.14.2+ adds fake-useragent and httpx' "" \
          --replace-fail '    # extras). Bump together with the cutoff.' ""
        substituteInPlace omlx/websearch.py \
          --replace-fail '# Text backends the pinned ddgs 9.14.1 actually registers (bing/google' '# Text backends the selected ddgs package registers (bing/google' \
          --replace-fail '    "yandex",' ""
        substituteInPlace omlx/admin/static/js/dashboard.js \
          --replace-fail '// Engines selectable for the DDGS Custom provider (ddgs 9.14.1 text registry)' '// Engines selectable for the DDGS Custom provider (selected DDGS text registry)' \
          --replace-fail "ddgsBackendList: ['brave', 'duckduckgo', 'grokipedia', 'mojeek', 'wikipedia', 'yahoo', 'yandex']," "ddgsBackendList: ['brave', 'duckduckgo', 'grokipedia', 'mojeek', 'wikipedia', 'yahoo'],"
        substituteInPlace pyproject.toml \
          --replace-fail '"cmake>=3.27",' "" \
          --replace-fail '"nanobind==2.13.0",' "" \
          --replace-fail '"mlx-lm @ git+https://github.com/ml-explore/mlx-lm@ab1806e8f5d6aa035973af194a1b9198ab4754dc"' '"mlx-lm"' \
          --replace-fail '"mlx-embeddings @ git+https://github.com/Blaizzy/mlx-embeddings@32981fa4e8064ed664b52071789dd18271fe4206"' '"mlx-embeddings"' \
          --replace-fail '"mlx-vlm @ git+https://github.com/Blaizzy/mlx-vlm@78b96eb5462141447b9a6b4943ef553891da56dd"' '"mlx-vlm"' \
          --replace-fail '"dflash-mlx @ git+https://github.com/${sources.dflash-mlx.source.args.owner}/${sources.dflash-mlx.source.args.repo}@${sources.dflash-mlx.source.args.rev}"' '"dflash-mlx"'
      '';

      build-system = [
        setuptools
        wheel
      ];

      nativeCheckInputs = [ packaging ];

      # Use the numpy and transformers versions shared by this MLX package set.
      # The checks below exercise imports and CLI startup with those versions.
      pythonRelaxDeps = [
        "numpy"
        "transformers"
      ];

      dependencies = [
        mlx
        mlx-lm
        mlx-embeddings
        mlx-vlm
        mlx-audio
        dflash-mlx
        ddgs
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
        rich
        sentencepiece
        tiktoken
        protobuf
        requests
        socksio
        tabulate
        psutil
        setproctitle
        fastapi
        uvicorn
        python-multipart
        jsonschema
        openai-harmony
        cohere-melody
        pillow
        # File conversion uses MarkItDown's document backends, not its optional
        # speech-recognition audio backend.
        (markitdown.override { speechrecognition = null; })
      ];

      # Python packages route doCheck through installCheckPhase; setting
      # doInstallCheck directly is ignored by mk-python-derivation.
      doCheck = true;
      pythonImportsCheck = [
        "omlx"
        "omlx.scheduler"
      ];

      # Smoke-test CLI startup and the installed Mach adapter.
      # Also exercise the installed Mach adapter with fake libc responses for
      # the current ABI count and a bounded future-kernel retry.
      installCheckPhase = ''
        runHook preInstallCheck
        $out/bin/omlx --help > /dev/null
        PYTHONPATH="$out/${python.sitePackages}:''${PYTHONPATH:-}" \
          ${python.interpreter} ${../test/ai/overlays/omlx-ddgs-version-contract.py} ${ddgs.version}
        PYTHONPATH="$out/${python.sitePackages}:''${PYTHONPATH:-}" \
          ${python.interpreter} ${../test/ai/overlays/omlx-mlx-version-contract.py} ${mlx.version}
        PYTHONPATH="$out/${python.sitePackages}:''${PYTHONPATH:-}" \
          ${python.interpreter} ${../test/ai/overlays/omlx-direct-reference-contract.py} ${mlx-embeddings.version} ${mlx-vlm.version}
        PYTHONPATH="$out/${python.sitePackages}:''${PYTHONPATH:-}" \
          ${python.interpreter} ${../test/ai/overlays/omlx-host-vm-info64-count.py}
        runHook postInstallCheck
      '';

      meta = {
        description = "LLM inference server optimized for Apple Silicon";
        homepage = "https://github.com/jundot/omlx";
        license = lib.licenses.asl20;
        platforms = [ "aarch64-darwin" ];
        mainProgram = "omlx";
      };
    };
}
