self: super:

let
  llm-mlx = {
    lib,
    callPackage,
    buildPythonPackage,
    fetchFromGitHub,
    setuptools,
    llm,
    mlx,
    pytestCheckHook,
    pytest-asyncio,
    pytest-recording,
    writableTmpDirAsHomeHook,
  }:
    buildPythonPackage rec {
      pname = "llm-mlx";
      version = "0.4";
      pyproject = true;

      src = fetchFromGitHub {
        owner = "simonw";
        repo = "llm-mlx";
        tag = version;
        hash = "sha256-9SGbvhuNeKgMYGa0ZiOLm+H/JbNpvFWBcUL4De5xO4o=";
      };

      build-system = [
        setuptools
        llm
      ];
      dependencies = [ mlx ];

      nativeCheckInputs = [
        pytestCheckHook
        pytest-asyncio
        pytest-recording
        writableTmpDirAsHomeHook
      ];

      pythonImportsCheck = [ "llm_mlx" ];

      passthru.tests = {
        llm-plugin = callPackage ./tests/llm-plugin.nix { };
      };

      meta = {
        description = "LLM access to models using MLX";
        homepage = "https://github.com/simonw/llm-mlx";
        changelog = "https://github.com/simonw/llm-mlx/releases/tag/${version}/CHANGELOG.md";
        license = lib.licenses.asl20;
        maintainers = with lib.maintainers; [ jwiegley ];
      };
    };
in
{

gguf-tools = with super; stdenv.mkDerivation rec {
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
    homepage = https://github.com/antirez/gguf-tools;
    description = "This is a work in progress library to manipulate GGUF files";
    license = lib.licenses.mit;
    maintainers = with lib.maintainers; [ jwiegley ];
  };
};

hfdownloader = with super; buildGoModule rec {
  pname = "hfdownloader";
  version = "2.0.0";
  vendorHash = "sha256-3xSLD0vEKedk/7LCxmKjHGuBvE9fd78aUoXYzmkDB1k=";

  src = fetchFromGitHub {
    owner = "bodaay";
    repo = "HuggingFaceModelDownloader";
    rev = "${version}";
    hash = "sha256-gVCsUoUMYNxp99q1XED3+i4C0gdplDeVs+tZrgnzH7M=";
  };

  meta = with lib; {
    description = "The HuggingFace Model Downloader is a utility tool for downloading models and datasets from the HuggingFace website";
    homepage = "https://github.com/bodaay/HuggingFaceModelDownloader";
    license = licenses.asl20;
    maintainers = [ maintainers.jwiegley ];
  };
};

llama-cpp = super.llama-cpp.overrideAttrs(attrs: rec {
  version = "7236";
  src = super.fetchFromGitHub {
    owner = "ggml-org";
    repo = "llama.cpp";
    tag = "b${version}";
    hash = "sha256-mwVUiPPtMvleOY1WE7vo1V/urhNO6AeD+BXjaMFM3Fk=";
  };
  # Fix macOS dylib version: 0.0.7236 exceeds max patch version (255)
  cmakeFlags = (attrs.cmakeFlags or []) ++ super.lib.optionals super.stdenv.hostPlatform.isDarwin [
    "-DLLAMA_BUILD_NUMBER=0"
  ];
});

llama-swap =
let
  version = "176";

  src = super.fetchFromGitHub {
    owner = "mostlygeek";
    repo = "llama-swap";
    rev = "v${version}";
    hash = "sha256-19vvuU5SD8lpaezNEY0FTkSVmpsouKh2SklsuFlTW+U=";
  };

  ui = with super; buildNpmPackage (finalAttrs: {
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
in
with super; llama-swap.overrideAttrs(attrs: rec {
  inherit version src;
  vendorHash = "sha256-/EbFyuCVFxHTTO0UwSV3B/6PYUpudxB2FD8nNx1Bb+M=";
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

mlx-lm = with self; with self.python3Packages; buildPythonApplication rec {
  pname = "mlx-lm";
  version = "0.28.2";
  pyproject = true;

  src = fetchFromGitHub {
    owner = "mlx-explore";
    repo = "mlx-lm";
    tag = version;
    hash = "sha256-6SGbvhuNeKgMYGa0ZiOLm+H/JbNpvFWBcUL4De5xO4o=";
  };

  build-system = [
    setuptools
    llm
  ];
  dependencies = [ mlx ];

  nativeCheckInputs = [
    pytestCheckHook
    pytest-asyncio
    pytest-recording
    writableTmpDirAsHomeHook
  ];

  meta = {
    description = "LLM access to models using MLX";
    homepage = "https://github.com/mlx-explore/mlx-lm";
    license = lib.licenses.mit;
    maintainers = with lib.maintainers; [ jwiegley ];
  };
};

pythonPackagesExtensions = (super.pythonPackagesExtensions or []) ++ [
  (pfinal: pprev:
    let
      nanobind = pprev.nanobind.overridePythonAttrs (oldAttrs: rec {
        version = "2.4.0";
        src = super.fetchFromGitHub {
          owner = "wjakob";
          repo = "nanobind";
          rev = "v${version}";
          fetchSubmodules = true;
          hash = "sha256-9OpDsjFEeJGtbti4Q9HHl78XaGf8M3lG4ukvHCMzyMU=";
        };
      });
   in {
    # Fix hash mismatch for mitmproxy-macos wheel (PyPI republished the package)
    mitmproxy-macos = pprev.mitmproxy-macos.overridePythonAttrs (oldAttrs: {
      src = pfinal.fetchPypi {
        pname = "mitmproxy_macos";
        inherit (oldAttrs) version;
        format = "wheel";
        dist = "py3";
        python = "py3";
        hash = "sha256-baAfEY4hEN3wOEicgE53gY71IX003JYFyyZaNJ7U8UA=";
      };
    });

    mlx = pprev.mlx.overridePythonAttrs (oldAttrs: rec {
      # version = "0.25.2";
      # src = super.fetchFromGitHub {
      #   owner = "ml-explore";
      #   repo = "mlx";
      #   rev = "refs/tags/v${version}";
      #   hash = "sha256-fkf/kKATr384WduFG/X81c5InEAZq5u5+hwrAJIg7MI=";
      # };
      patches = [];
      env = {
        PYPI_RELEASE = oldAttrs.version;
        CMAKE_ARGS = with self; toString [
          # (lib.cmakeBool "MLX_BUILD_METAL" true)
          (lib.cmakeOptionType "filepath" "FETCHCONTENT_SOURCE_DIR_GGUFLIB" "${gguf-tools}")
          (lib.cmakeOptionType "filepath" "FETCHCONTENT_SOURCE_DIR_JSON" "${nlohmann_json}")
        ];
      };
      # buildInputs = (oldAttrs.buildInputs or []) ++ [
      #   self.darwin.apple_sdk_14_4
      # ];
      # nativeBuildInputs = (oldAttrs.nativeBuildInputs or []) ++ [
      #   nanobind
      # ];
    });

    llm-mlx = pfinal.callPackage llm-mlx {};
  })
];

rustdocs-mcp-server = with super; rustPlatform.buildRustPackage rec {
  pname = "rustdocs-mcp-server";
  version = "1.3.1";

  src = fetchFromGitHub {
    owner = "Govcraft";
    repo = "rust-docs-mcp-server";
    rev = "v${version}";
    hash = "sha256-jSa4qKZEtZZvYfoRReGDDqH039RH/7Dimo3jmcnnwak=";
  };

  cargoHash = "sha256-iw7dRzwH42HBj2r9y5IHHKLmER7QkyFzLjh7Q+dNMao=";

  nativeBuildInputs = [
    pkg-config
    perl
    openssl.dev
  ];

  meta = with lib; {
    description = ''
      Fetches the documentation for a specified Rust crate, generates
      embeddings for the content, and provides an MCP tool to answer questions
      about the crate based on the documentation context.
    '';
    homepage = "https://github.com/Govcraft/rust-docs-mcp-server";
    license = licenses.mit;
    maintainers = with maintainers; [ jwiegley ];
    mainProgram = "rustdocs_mcp_server";
  };
};

task-master-ai-latest = with super; buildNpmPackage (finalAttrs: {
  pname = "task-master-ai";
  version = "0.28.0";

  src = fetchFromGitHub {
    owner = "eyaltoledano";
    repo = "claude-task-master";
    tag = "task-master-ai@${finalAttrs.version}";
    hash = "sha256-qbqcJkopKf8cEslWfnhj9AYbkX/ViGm3tk5K2LIPNjo=";
  };

  postPatch = ''
    cp ${./package-lock.json} package-lock.json
  '';
  npmDepsHash = "sha256-2mO3+Pc+ZuCjzBAsZParTc8lYn9uhMhe75UA1OLnHmw=";

  dontNpmBuild = true;

  npmFlags = [ "--ignore-scripts" ];

  makeWrapperArgs = [ "--prefix PATH : ${lib.makeBinPath [ nodejs ]}" ];

  passthru.updateScript = nix-update-script { };

  postInstall = ''
    mkdir -p $out/lib/node_modules/task-master-ai/apps
    cp -r apps/extension $out/lib/node_modules/task-master-ai/apps/extension
    cp -r apps/docs $out/lib/node_modules/task-master-ai/apps/docs
  '';

  env = {
    PUPPETEER_SKIP_DOWNLOAD = 1;
  };

  nativeInstallCheckInputs = [ versionCheckHook ];
  doInstallCheck = true;
  versionCheckProgram = "${placeholder "out"}/bin/task-master";
  versionCheckProgramArg = "--version";

  meta = with lib; {
    description = "Node.js agentic AI workflow orchestrator";
    homepage = "https://task-master.dev";
    changelog = "https://github.com/eyaltoledano/claude-task-master/blob/${finalAttrs.src.tag}/CHANGELOG.md";
    license = licenses.mit;
    mainProgram = "task-master-ai";
    maintainers = [ maintainers.repparw ];
    platforms = platforms.all;
  };
});

browser-control-mcp = with super; buildNpmPackage (finalAttrs: {
  pname = "browser-control-mcp";
  version = "1.5.1";

  src = fetchFromGitHub {
    owner = "eyalzh";
    repo = "browser-control-mcp";
    tag = "v${finalAttrs.version}";
    hash = "sha256-P0ZYjaHArngobtOf4C3j3LpuwfT4vZdJnoZnzeNoIWo=";
  };

  # postPatch = ''
  #   cp ${./package-lock.json} package-lock.json
  # '';
  npmDepsHash = "sha256-NT0r3WHqg6ENVO4aPldUgs2doDJD+EEJcp78nNfbBnQ=";

  # dontNpmBuild = true;

  # npmFlags = [ "--ignore-scripts" ];

  makeWrapperArgs = [ "--prefix PATH : ${lib.makeBinPath [ nodejs ]}" ];

  passthru.updateScript = nix-update-script { };

  # postInstall = ''
  #   mkdir -p $out/lib/node_modules/task-master-ai/apps
  #   cp -r apps/extension $out/lib/node_modules/task-master-ai/apps/extension
  #   cp -r apps/docs $out/lib/node_modules/task-master-ai/apps/docs
  # '';

  # env = {
  #   PUPPETEER_SKIP_DOWNLOAD = 1;
  # };

  # nativeInstallCheckInputs = [ versionCheckHook ];
  doInstallCheck = true;
  versionCheckProgram = "${placeholder "out"}/bin/browser-control-mcp";
  versionCheckProgramArg = "--version";

  meta = with lib; {
    description = "MCP server paired with a browser extension that enables AI agents to control the user's browser.";
    homepage = "https://github.com/eyalzh/browser-control-mcp";
    license = licenses.mit;
    mainProgram = "browser-control-mcp";
    maintainers = [ maintainers.jwiegley ];
    platforms = platforms.all;
  };
});

claude-code-acp = with self; buildNpmPackage (finalAttrs: {
  pname = "claude-code-acp";
  version = "0.4.5";

  src = fetchFromGitHub {
    owner = "zed-industries";
    repo = "claude-code-acp";
    rev = "v${finalAttrs.version}";
    hash = "sha256-kkAQuYP2S5EwIGJV8TLrlYzHOC54vmxEHwwuZD5P1hI=";
  };

  npmDepsHash = "sha256-IR88NP1AiR6t/MLDdaZY1Np0AE7wfqEUfmnohaf0ymc=";

  dontNpmBuild = false;

  npmFlags = [
    "--ignore-scripts"
  ];

  makeWrapperArgs = [ "--prefix PATH : ${lib.makeBinPath [ nodejs ]}" ];

  passthru.updateScript = nix-update-script { };

  # Version check disabled - command doesn't support --version flag
  doInstallCheck = false;

  meta = with lib; {
    description = "Use Claude Code from any ACP-compatible clients such as Zed";
    homepage = "https://github.com/zed-industries/claude-code-acp";
    license = licenses.asl20;
    mainProgram = "claude-code-acp";
    maintainers = [ maintainers.jwiegley ];
    platforms = platforms.all;
  };
});

}
