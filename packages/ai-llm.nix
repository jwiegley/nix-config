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
      doCheck = false; # Tests include timing-sensitive server cancellation checks.

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

          # llama-swap 219 relocated the svelte build output from
          # ../proxy/ui_dist to ../internal/server/ui_dist (see
          # ui-svelte/vite.config.ts). Redirect it to this derivation's $out so
          # vite writes into a writable path instead of the read-only source
          # tree. --replace-fail aborts if the upstream literal ever changes
          # again (the old silent --replace is what left this build broken on
          # the 217->219 bump).
          postPatch = ''
            substituteInPlace vite.config.ts \
            --replace-fail '"../internal/server/ui_dist"' '"${placeholder "out"}/ui_dist"'
          '';

          sourceRoot = "source/ui-svelte";

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
        # llama-swap 219 serves the web UI from internal/server/ui_dist
        # (//go:embed in internal/server/ui.go, where the main binary reads
        # it). The repo ships only a placeholder.txt there to keep the embed
        # valid before a build, so replace it with the real vite output.
        rm -rf internal/server/ui_dist
        cp -r ${ui}/ui_dist internal/server/

        # cmd/legacy still imports the proxy package, whose ui_embed.go also
        # has //go:embed ui_dist. That directory is not shipped in the source
        # tarball, so create it too or the (default subPackages=null) build of
        # cmd/legacy fails with "pattern ui_dist: no matching files found".
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

  # AIPerf - Generative AI model-server benchmarking
  aiperf =
    let
      # AIPerf 0.11.0 requires Python >=3.10,<3.14. nixpkgs' default Python is
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

        # The compiled extensions import NumPy at runtime even though crick's
        # upstream wheel metadata does not declare that dependency.
        dependencies = [ ps.numpy ];

        # Upstream tests import the source tree before the Cython extensions
        # are installed and fail collection with a missing crick.numpy_version.
        # Retain the installed-module check and exercise TDigest below.
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

      # AIPerf 0.11.0 declares kaleido~=1.2.0. Keep the catalog target manual
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

        # The wheel bundles a browser-bearing suite that needs Chrome and
        # additional test-only dependencies. Keep the browser external while
        # retaining the import check and AIPerf's plugin validation below.
        doCheck = false;
        pythonImportsCheck = [ "kaleido" ];

        meta = {
          description = "Static image export for web-based visualization libraries";
          homepage = "https://github.com/plotly/Kaleido";
          license = prev.lib.licenses.mit;
        };
      };

      # This rendering-sensitive assertion is the sole failure on Hera:
      # 2274 passed, 59 skipped, 5 xfailed, 1 failed.
      aiperfSeaborn = ps.seaborn.overridePythonAttrs (old: {
        disabledTests =
          (old.disabledTests or [ ])
          ++ prev.lib.optionals prev.stdenv.isDarwin [
            "test_ticklabels_overlap"
          ];
      });

      # Cyclopts' interactive Zsh harness nondeterministically fails to reach
      # its prompt in the Darwin sandbox. Remove only Zsh from that one
      # cross-shell matrix; static Zsh tests and Bash/Fish behavior stay on.
      aiperfCyclopts =
        if prev.stdenv.hostPlatform.isDarwin then
          ps.cyclopts.overridePythonAttrs (old: {
            postPatch = (old.postPatch or "") + ''
              substituteInPlace tests/completion/test_behavior.py \
                --replace-fail 'params=["bash", "zsh", "fish"]' \
                'params=["bash", "fish"]'
            '';
            disabledTests = (old.disabledTests or [ ]) ++ [
              "test_choice_with_whitespace"
              "test_choice_with_backtick"
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
          aiperfSeaborn
        ];

      # These pinned nixpkgs packages are newer than AIPerf's compatible-release
      # constraints. Keep every other runtime constraint check active.
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

      # The wheel contains no source test suite. Exercise the installed CLI
      # and packaged resources in installCheckPhase instead.
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
        mainProgram = "guidellm";
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
          inherit (sources.mtplx) version;
          pyproject = null;
          format = "wheel";

          src =
            assert sources.mtplx.source.fetcher == "fetchPypi";
            fetchPypi sources.mtplx.source.args;

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
          mainProgram = "mtplx";
        };
      }
      ''
        mkdir -p $out/bin
        ln -s ${pyEnv}/bin/mtplx $out/bin/mtplx
        ln -s ${pyEnv}/bin/mtplx-tune $out/bin/mtplx-tune
      '';

  # omlx - LLM inference server optimized for Apple Silicon
  # NOTE: omlx requires Python >=3.11,<3.14. Keep the complete application on
  # Python 3.13 so its native MLX and Cohere wheels share one ABI, while still
  # resolving deps against our extended package set (mlx wheel override,
  # mlx-embeddings, dflash-mlx). omlx itself is pure Python; the Homebrew
  # formula's Rust dependency was only for transitive wheels.
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
      # v0.5.0 added cmake/nanobind to [build-system] requires for the
      # optional custom Metal kernels (omlx.custom_kernels.*, gated behind
      # OMLX_WITH_CUSTOM_KERNEL in setup.py, default off). We don't build
      # them — the Metal toolchain is unavailable in the sandbox — but
      # `python -m build --no-isolation` still validates build requires,
      # so drop the two we don't supply. The mlx==0.32.0 build requirement
      # stays: it's satisfied by our mlx wheel override.
      postPatch = ''
        substituteInPlace pyproject.toml \
          --replace-fail '"cmake>=3.27",' "" \
          --replace-fail '"nanobind==2.13.0",' "" \
          --replace-fail '"mlx-lm @ git+https://github.com/ml-explore/mlx-lm@ab1806e8f5d6aa035973af194a1b9198ab4754dc"' '"mlx-lm"' \
          --replace-fail '"mlx-embeddings @ git+https://github.com/Blaizzy/mlx-embeddings@32981fa4e8064ed664b52071789dd18271fe4206"' '"mlx-embeddings"' \
          --replace-fail '"mlx-vlm @ git+https://github.com/Blaizzy/mlx-vlm@78b96eb5462141447b9a6b4943ef553891da56dd"' '"mlx-vlm"' \
          --replace-fail '"dflash-mlx @ git+https://github.com/jundot/dflash-mlx@474f8e1ba95864f5bb0759cd1b9a13c80abc5ce3"' '"dflash-mlx"'
      '';

      build-system = [
        setuptools
        wheel
      ];

      # v0.4.4's pyproject pins numpy<2.4 and transformers>=5.7.0, but the
      # entire mlx stack in this overlay is built against nixpkgs' numpy 2.4.x
      # and transformers 5.5.x. omlx itself only uses stable numpy array ops,
      # and the import/CLI smoke checks pass with the local transformers.
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
        # v0.4.4 includes markitdown[pdf,docx,pptx]==0.1.6; server.py imports
        # omlx.api.markitdown at module load. nixpkgs' markitdown 0.1.6 already
        # propagates the pdf (pdfplumber/pdfminer-six), docx (mammoth), and
        # pptx (python-pptx) backends omlx actually uses for file conversion.
        #
        # Drop the speechrecognition input: it is markitdown's audio backend
        # (omlx never transcribes audio via markitdown) and currently drags in
        # faster-whisper -> av, where nixpkgs builds av against a different
        # python3 patch release than the rest of the set, which throws a
        # "Python version mismatch" at eval. Nulling it keeps every document
        # backend while sidestepping the broken audio subtree.
        (markitdown.override { speechrecognition = null; })
      ];

      # Python packages route doCheck through installCheckPhase; setting
      # doInstallCheck directly is ignored by mk-python-derivation.
      doCheck = true;
      pythonImportsCheck = [ "omlx" ];

      # Smoke test that the wrapped entry point runs. omlx's CLI uses
      # subcommands (serve/launch/diagnose) and has no --version flag, so
      # exercise --help, which builds the full argparse tree and exits 0.
      # Also exercise the installed Mach adapter with fake libc responses for
      # the current ABI count and a bounded future-kernel retry.
      installCheckPhase = ''
        runHook preInstallCheck
        $out/bin/omlx --help > /dev/null
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
