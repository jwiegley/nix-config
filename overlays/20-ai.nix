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
  version = "1.95.1";

  src = super.fetchFromGitHub {
    owner = "LostRuins";
    repo = "koboldcpp";
    tag = "v${version}";
    hash = "sha256-aoVOEPK3hPuzkrHIFvDrnAw2D/OxXlRLXXP0CZJghx4=";
  };
});

ik-llama-cpp = super.llama-cpp.overrideAttrs(attrs: rec {
  version = "b57bd865";

  src = super.fetchFromGitHub {
    owner = "ikawrakow";
    repo = "ik_llama.cpp";
    rev = "b57bd8658bfb20e65ad0b601eef6732fee45b81f";
    sha256 = "06ad8458h1rsr91irkq6s5pbkrk3r3lpk5867yr76s4jxfqnwakx";
    # date = "2025-06-12T19:25:11+03:00";
  };
});

llama-cpp = super.llama-cpp.overrideAttrs(attrs: rec {
  version = "5849";
  src = super.fetchFromGitHub {
    owner = "ggml-org";
    repo = "llama.cpp";
    tag = "b${version}";
    hash = "sha256-1jCnvCeI6I2byyqvaYT8Kffslf/LG+mj9IAGhtFliL0=";
  };
});

llama-swap =
let
  version = "139";

  src = super.fetchFromGitHub {
    owner = "mostlygeek";
    repo = "llama-swap";
    rev = "v${version}";
    hash = "sha256-1N2IXESA/AtiEJCBQpuUayMzEYuJmN1PJ3c+mdT7RrM=";
  };

  ui = with super; buildNpmPackage (finalAttrs: {
    pname = "llama-swap-ui";
    inherit version src;

    postPatch = ''
      substituteInPlace vite.config.ts \
      --replace '../proxy/ui_dist' '${placeholder "out"}/ui_dist'
    '';

    sourceRoot = "source/ui";

    npmDepsHash = "sha256-smdqD1X9tVr0XMhQYpLBZ57/3iP8tYVoVJ2wR/gAC3w=";

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
  vendorHash = "sha256-5mmciFAGe8ZEIQvXejhYN+ocJL3wOVwevIieDuokhGU=";
  preBuild = ''
    cp -r ${ui}/ui_dist proxy/
  '';
  ldflags = [
    "-X main.version=${version}"
    "-X main.date=unknown"
    "-X main.commit=v${version}"
  ];
  meta = {
    description = "Model swapping for llama.cpp (or any local OpenAPI compatible server)";
    license = lib.licenses.mit;
    platforms = lib.platforms.unix;
    mainProgram = "llama-swap";
  };
});

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
