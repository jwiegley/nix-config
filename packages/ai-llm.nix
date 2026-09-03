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

          # Extend MTPLX's Transformers guard through the selected 5.16.1; the
          # install check below verifies its metadata and MLX tokenizer import path.
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
            from pathlib import Path
            from tempfile import TemporaryDirectory

            from packaging.requirements import Requirement
            from packaging.version import Version
            from tokenizers import Tokenizer
            from tokenizers.models import WordLevel
            from tokenizers.pre_tokenizers import Whitespace
            from transformers import PreTrainedTokenizerFast
            import mtplx.runtime
            import transformers
            from mlx_lm.tokenizer_utils import TokenizerWrapper
            from mlx_lm.utils import load_tokenizer

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
            assert Version("5.16.0") in requirement.specifier, requirement
            assert Version("5.16.999") in requirement.specifier, requirement
            assert Version("5.17.0") not in requirement.specifier, requirement
            assert str(requirement.marker) == (
                'sys_platform == "darwin" and platform_machine == "arm64"'
            ), requirement

            selected = Version(transformers.__version__)
            assert selected.release[:2] == (5, 16), selected
            assert selected in requirement.specifier, (selected, requirement)
            with TemporaryDirectory() as temp_dir:
                tokenizer = Tokenizer(WordLevel({"[UNK]": 0, "hello": 1}, unk_token="[UNK]"))
                tokenizer.pre_tokenizer = Whitespace()
                PreTrainedTokenizerFast(
                    tokenizer_object=tokenizer,
                    unk_token="[UNK]",
                ).save_pretrained(temp_dir)
                loaded = load_tokenizer(Path(temp_dir))
                assert isinstance(loaded, TokenizerWrapper)
                assert loaded.encode("hello") == [1]
            assert callable(mtplx.runtime._load_tokenizer_resilient)
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

  # Build omlx in a release-scoped Python package set so exact upstream pins
  # cannot drift with the independently updateable shared MLX stack.
  omlx =
    let
      omlxPython = final.python313.override {
        packageOverrides =
          pfinal: pprev:
          let
            omlxMlxMetal =
              assert sources.omlx-mlx.artifacts.metal.fetcher == "fetchPypi";
              pfinal.fetchPypi sources.omlx-mlx.artifacts.metal.args;
          in
          {
            mlx = pprev.mlx.overridePythonAttrs (_oldAttrs: {
              inherit (sources.omlx-mlx) version;
              src =
                assert sources.omlx-mlx.source.fetcher == "fetchPypi";
                pfinal.fetchPypi sources.omlx-mlx.source.args;
              postInstall = ''
                unzip -o ${omlxMlxMetal} -d $TMPDIR/mlx-metal
                siteDir=$out/${pfinal.python.sitePackages}/mlx
                cp -r $TMPDIR/mlx-metal/mlx/lib      $siteDir/
                cp -r $TMPDIR/mlx-metal/mlx/include  $siteDir/
                cp -r $TMPDIR/mlx-metal/mlx/share    $siteDir/
              '';
            });

            numpy = pprev.numpy.overridePythonAttrs (_oldAttrs: {
              inherit (sources.omlx-numpy) version;
              src =
                assert sources.omlx-numpy.source.fetcher == "fetchPypi";
                pfinal.fetchPypi sources.omlx-numpy.source.args;
              patches = [ ];
            });

            # FastAPI's server-only closure does not participate in the ML ABI.
            # Reuse it as one coherent package family rather than rebuilding its
            # timing-sensitive HTTP test dependencies under the NumPy override.
            inherit (final.python313Packages)
              annotated-doc
              annotated-types
              anyio
              fastapi
              idna
              pydantic
              pydantic-core
              starlette
              pillow
              typing-extensions
              typing-inspection
              ;

            markitdown =
              (final.python313Packages.markitdown.override { speechrecognition = null; }).overridePythonAttrs
                (oldAttrs: {
                  dependencies = map (
                    dependency:
                    let
                      name = dependency.pname or "";
                    in
                    if name == "magika" then
                      pfinal.magika
                    else if name == "pandas" then
                      pfinal.pandas
                    else
                      dependency
                  ) (oldAttrs.dependencies or [ ]);
                });

            tokenizers = pprev.tokenizers.overridePythonAttrs (_oldAttrs: {
              inherit (sources.omlx-tokenizers) version;
              format = "wheel";
              pyproject = null;
              src =
                assert sources.omlx-tokenizers.source.fetcher == "fetchPypi";
                pfinal.fetchPypi sources.omlx-tokenizers.source.args;
              cargoDeps = null;
              nativeBuildInputs = [ ];
              nativeCheckInputs = [ ];
              postUnpack = "";
              sourceRoot = ".";
              doCheck = false;
            });

            transformers = pprev.transformers.overridePythonAttrs (_oldAttrs: {
              inherit (sources.omlx-transformers) version;
              src =
                assert sources.omlx-transformers.source.fetcher == "fetchPypi";
                pfinal.fetchPypi sources.omlx-transformers.source.args;
            });

            ddgs = pprev.ddgs.overridePythonAttrs (_oldAttrs: {
              inherit (sources.omlx-ddgs) version;
              src =
                assert sources.omlx-ddgs.source.fetcher == "fetchFromGitHub";
                final.fetchFromGitHub sources.omlx-ddgs.source.args;
              dependencies = (pprev.ddgs.dependencies or [ ]) ++ [
                pfinal.brotli
                pfinal.fake-useragent
                pfinal.h2
                pfinal.httpx
                pfinal.socksio
              ];
              installCheckPhase = ''
                runHook preInstallCheck
                PYTHONPATH="$out/${pfinal.python.sitePackages}:''${PYTHONPATH:-}" \
                  ${pfinal.python.interpreter} ${../test/ai/overlays/ddgs-dependency-contract.py} ${sources.omlx-ddgs.version}
                runHook postInstallCheck
              '';
            });

            librosa = pfinal.buildPythonPackage {
              pname = "librosa";
              inherit (sources.omlx-librosa) version;
              pyproject = true;
              src =
                assert sources.omlx-librosa.source.fetcher == "fetchPypi";
                pfinal.fetchPypi sources.omlx-librosa.source.args;
              build-system = [ pfinal.setuptools ];
              dependencies = with pfinal; [
                audioread
                decorator
                joblib
                lazy-loader
                msgpack
                numba
                numpy
                pooch
                scikit-learn
                scipy
                soundfile
                soxr
                standard-aifc
                standard-sunau
                typing-extensions
              ];
              doCheck = false;
              pythonImportsCheck = [ "librosa" ];
            };

            sounddevice = pprev.sounddevice.overridePythonAttrs (_oldAttrs: {
              inherit (sources.omlx-sounddevice) version;
              src =
                assert sources.omlx-sounddevice.source.fetcher == "fetchPypi";
                pfinal.fetchPypi sources.omlx-sounddevice.source.args;
              patches = [
                (final.replaceVars ../overlays/ai/patches/sounddevice-0.5.3-portaudio.patch {
                  portaudio = "${final.portaudio}/lib/libportaudio${final.stdenv.hostPlatform.extensions.sharedLibrary}";
                })
              ];
            });

            mlx-audio = pprev.mlx-audio.overridePythonAttrs (oldAttrs: {
              inherit (sources.omlx-mlx-audio) version;
              src =
                assert sources.omlx-mlx-audio.source.fetcher == "fetchFromGitHub";
                final.fetchFromGitHub sources.omlx-mlx-audio.source.args;
              # oMLX's declared resolver override selects its newer exact
              # mlx-lm commit over mlx-audio's transitive 0.31.1 pin.
              postPatch = (oldAttrs.postPatch or "") + ''
                substituteInPlace pyproject.toml \
                  --replace-fail '"mlx-lm==0.31.1"' '"mlx-lm"'
              '';
              installCheckPhase = ''
                runHook preInstallCheck
                PYTHONPATH="$out/${pfinal.python.sitePackages}:''${PYTHONPATH:-}" \
                  ${pfinal.python.interpreter} ${../test/ai/overlays/mlx-audio-version-contract.py} ${sources.omlx-mlx-audio.version}
                runHook postInstallCheck
              '';
            });

            mlx-vlm = pprev.mlx-vlm.overridePythonAttrs (oldAttrs: {
              inherit (sources.omlx-mlx-vlm) version;
              src =
                assert sources.omlx-mlx-vlm.source.fetcher == "fetchFromGitHub";
                final.fetchFromGitHub sources.omlx-mlx-vlm.source.args;
              patches = (oldAttrs.patches or [ ]) ++ [
                ../overlays/ai/patches/mlx-vlm-omlx-quantization-aliases.patch
              ];
              dependencies = oldAttrs.dependencies ++ [
                pfinal.datasets
                pfinal.mlx-lm
              ];
              installCheckPhase = ''
                runHook preInstallCheck
                PYTHONPATH="$out/${pfinal.python.sitePackages}:''${PYTHONPATH:-}" \
                  ${pfinal.python.interpreter} ${../test/ai/overlays/mlx-vlm-dependency-contract.py} ${sources.omlx-mlx-vlm.version}
                runHook postInstallCheck
              '';
            });

            mlx-embeddings = pfinal.buildPythonPackage {
              pname = "mlx-embeddings";
              inherit (sources.omlx-mlx-embeddings) version;
              pyproject = true;
              src =
                assert sources.omlx-mlx-embeddings.source.fetcher == "fetchFromGitHub";
                final.fetchFromGitHub sources.omlx-mlx-embeddings.source.args;
              build-system = [ pfinal.setuptools ];
              dependencies = with pfinal; [
                mlx
                mlx-vlm
                transformers
                huggingface-hub
                sentencepiece
              ];
              pythonImportsCheck = [ "mlx_embeddings" ];
            };
          };
      };
      pythonPackages = omlxPython.pkgs;
    in
    with final;
    with pythonPackages;
    buildPythonApplication rec {
      pname = "omlx";
      version = sources.omlx.version;
      pyproject = true;

      src =
        assert sources.omlx.source.fetcher == "fetchFromGitHub";
        fetchFromGitHub sources.omlx.source.args;

      patches = [
        ../overlays/ai/patches/omlx-host-vm-info64-count.patch
        ../overlays/ai/patches/omlx-glm5-next-quantized-load.patch
      ];

      # Validate every release-coupled coordinate before translating direct
      # references into Nix package dependencies. Any future upstream drift
      # therefore fails before an incompatible closure can be built.
      postPatch = ''
        require_bare_exact_requirements() {
          local dependency=$1 expected=$2 expected_count=$3
          local -a coordinates
          mapfile -t coordinates < <(
            grep -Eo "\"$dependency==[^\"]*\"" pyproject.toml
          )
          if [[ ''${#coordinates[@]} -ne $expected_count ]]; then
            echo "oMLX must declare exactly $expected_count bare $dependency==$expected requirements, found ''${#coordinates[@]}" >&2
            return 1
          fi
          local coordinate
          for coordinate in "''${coordinates[@]}"; do
            if [[ $coordinate != "\"$dependency==$expected\"" ]]; then
              echo "oMLX must declare exactly $dependency==$expected, got $coordinate" >&2
              return 1
            fi
          done
        }

        replace_direct_reference() {
          local dependency=$1 expected=$2 replacement=$3
          if ! grep -Fq "$expected" pyproject.toml; then
            echo "oMLX must declare the exact $dependency source coordinate: $expected" >&2
            return 1
          fi
          substituteInPlace pyproject.toml \
            --replace-fail "$expected" "$replacement"
        }

        require_bare_exact_requirements mlx ${sources.omlx-mlx.version} 3
        require_bare_exact_requirements ddgs ${sources.omlx-ddgs.version} 1
        replace_direct_reference \
          mlx-lm \
          '"mlx-lm @ git+https://github.com/${sources.mlx-lm.source.args.owner}/${sources.mlx-lm.source.args.repo}@${sources.mlx-lm.source.args.rev}"' \
          '"mlx-lm"'
        replace_direct_reference \
          mlx-embeddings \
          '"mlx-embeddings @ git+https://github.com/${sources.omlx-mlx-embeddings.source.args.owner}/${sources.omlx-mlx-embeddings.source.args.repo}@${sources.omlx-mlx-embeddings.source.args.rev}"' \
          '"mlx-embeddings"'
        replace_direct_reference \
          mlx-vlm \
          '"mlx-vlm @ git+https://github.com/${sources.omlx-mlx-vlm.source.args.owner}/${sources.omlx-mlx-vlm.source.args.repo}@${sources.omlx-mlx-vlm.source.args.rev}"' \
          '"mlx-vlm"'
        replace_direct_reference \
          dflash-mlx \
          '"dflash-mlx @ git+https://github.com/${sources.dflash-mlx.source.args.owner}/${sources.dflash-mlx.source.args.repo}@${sources.dflash-mlx.source.args.rev}"' \
          '"dflash-mlx"'
        replace_direct_reference \
          mlx-audio \
          '"mlx-audio[tts,stt,sts] @ git+https://github.com/${sources.omlx-mlx-audio.source.args.owner}/${sources.omlx-mlx-audio.source.args.repo}@${sources.omlx-mlx-audio.source.args.rev}"' \
          '"mlx-audio[tts,stt,sts]"'
        if grep -Eq '"(mlx-lm|mlx-embeddings|mlx-vlm|dflash-mlx|mlx-audio)[^\"]* @ git\+' pyproject.toml; then
          echo "oMLX declares an unexpected direct dependency coordinate" >&2
          return 1
        fi
        unset -f require_bare_exact_requirements replace_direct_reference

        # DDGS 9.15 ships the Yandex engine module disabled, while oMLX 0.6.4
        # still advertises it in both server and dashboard policy.
        substituteInPlace omlx/websearch.py \
          --replace-fail '    "yandex",' ""
        substituteInPlace omlx/admin/static/js/dashboard.js \
          --replace-fail "ddgsBackendList: ['brave', 'duckduckgo', 'grokipedia', 'mojeek', 'wikipedia', 'yahoo', 'yandex']," "ddgsBackendList: ['brave', 'duckduckgo', 'grokipedia', 'mojeek', 'wikipedia', 'yahoo'],"

        substituteInPlace pyproject.toml \
          --replace-fail '"cmake>=3.27",' "" \
          --replace-fail '"nanobind==2.13.0",' ""
      '';

      build-system = [
        setuptools
        wheel
      ];

      nativeCheckInputs = [ packaging ];

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
        markitdown
      ];

      # Python packages route doCheck through installCheckPhase; setting
      # doInstallCheck directly is ignored by mk-python-derivation.
      doCheck = true;
      pythonImportsCheck = [
        "omlx"
        "omlx.scheduler"
      ];

      installCheckPhase = ''
        runHook preInstallCheck
        $out/bin/omlx --help > /dev/null
        PYTHONPATH="$out/${python.sitePackages}:''${PYTHONPATH:-}" \
          ${python.interpreter} ${../test/ai/overlays/omlx-ddgs-version-contract.py} ${ddgs.version}
        PYTHONPATH="$out/${python.sitePackages}:''${PYTHONPATH:-}" \
          ${python.interpreter} ${../test/ai/overlays/omlx-ddgs-dispatch-contract.py}
        PYTHONPATH="$out/${python.sitePackages}:''${PYTHONPATH:-}" \
          ${python.interpreter} ${../test/ai/overlays/omlx-mlx-version-contract.py} ${mlx.version}
        PYTHONPATH="$out/${python.sitePackages}:''${PYTHONPATH:-}" \
          ${python.interpreter} ${../test/ai/overlays/omlx-direct-reference-contract.py} ${mlx-embeddings.version} ${mlx-vlm.version}
        PYTHONPATH="$out/${python.sitePackages}:''${PYTHONPATH:-}" \
          ${python.interpreter} ${../test/ai/overlays/omlx-release-dependency-contract.py} \
            mlx ${mlx.version} \
            mlx-embeddings ${mlx-embeddings.version} \
            mlx-vlm ${mlx-vlm.version} \
            mlx-audio ${mlx-audio.version} \
            dflash-mlx ${dflash-mlx.version} \
            ddgs ${ddgs.version} \
            transformers ${transformers.version} \
            numpy ${numpy.version} \
            librosa ${librosa.version} \
            sounddevice ${sounddevice.version}
        PYTHONPATH="$out/${python.sitePackages}:''${PYTHONPATH:-}" \
          ${python.interpreter} ${../test/ai/overlays/omlx-glm5-next-contract.py}
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
