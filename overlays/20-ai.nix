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
  version = "8fa6eb65";

  src = fetchFromGitHub {
    owner = "antirez";
    repo = "gguf-tools";
    rev = "8fa6eb65236618e28fd7710a0fba565f7faa1848";
    sha256 = "084xwlqa6qq8ns2fzxvmgxhacgv7wy1l4mppwsmk7ac5yg46z4fp";
    # date = 2025-01-09T16:46:11+01:00;
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
  version = "1.4.2";
  vendorHash = "sha256-0tAJEPJQJTUYoV0IU2YYmSV60189rDRdwoxQsewkMEU=";

  src = fetchFromGitHub {
    owner = "bodaay";
    repo = "HuggingFaceModelDownloader";
    rev = "${version}";
    hash = "sha256-sec+NGh1I5YmQif+ifm+AJmG6TVKOW/enffh8UE0I+E=";
  };

  meta = with lib; {
    description = "The HuggingFace Model Downloader is a utility tool for downloading models and datasets from the HuggingFace website";
    homepage = "https://github.com/bodaay/HuggingFaceModelDownloader";
    license = licenses.asl20;
    maintainers = [ maintainers.jwiegley ];
  };
};

koboldcpp = super.koboldcpp.overrideAttrs(attrs: rec {
  version = "1.91";

  src = super.fetchFromGitHub {
    owner = "LostRuins";
    repo = "koboldcpp";
    tag = "v${version}";
    hash = "sha256-s2AfdKF4kUez3F1P+FYMbP2KD+J6+der/datxrdTiZU=";
  };
});

llama-cpp = super.llama-cpp.overrideAttrs(attrs: rec {
  version = "5624";

  src = super.fetchFromGitHub {
    owner = "ggml-org";
    repo = "llama.cpp";
    tag = "b${version}";
    hash = "sha256-7TA8NHwbW1pH6KwxYteNLircR7g1awQOK88PHuzrMcY=";
  };
});

llama-swap = with super; buildGoModule rec {
  pname = "llama-swap";
  version = "125";
  vendorHash = "sha256-5mmciFAGe8ZEIQvXejhYN+ocJL3wOVwevIieDuokhGU="
;
  src = fetchFromGitHub {
    owner = "mostlygeek";
    repo = "llama-swap";
    rev = "v${version}";
    hash = "sha256-mFmrHTexcVYMu58dvrTYB6wtDQOo5ZoiJL2jt29xJ0s=";
  };

  doCheck = false;

  meta = with lib; {
    description = "llama-swap is a light weight, transparent proxy server that provides automatic model swapping to llama.cpp's server";
    homepage = "https://github.com/mostlygeek/llama-swap";
    license = licenses.mit;
    maintainers = [ maintainers.jwiegley ];
  };
};

mlx-lm = with self; with self.python3Packages; buildPythonApplication rec {
  pname = "mlx-lm";
  version = "0.25.1";
  pyproject = true;

  src = fetchFromGitHub {
    owner = "mlx-explore";
    repo = "mlx-lm";
    tag = version;
    hash = "sha256-7SGbvhuNeKgMYGa0ZiOLm+H/JbNpvFWBcUL4De5xO4o=";
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

}
