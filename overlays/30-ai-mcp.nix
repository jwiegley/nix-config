# overlays/30-ai-mcp.nix
# Purpose: Model Context Protocol (MCP) servers and Claude Code tools
# Dependencies: Uses final for python3Packages; uses prev elsewhere
# Packages: pal-mcp-server, mcp-server-sequential-thinking, rustdocs-mcp-server,
#           browser-control-mcp, context-hub
final: prev:

prev.lib.optionalAttrs (prev ? inputs && prev.inputs ? pal-mcp-server) {

  # PAL MCP Server - Provider Abstraction Layer for multi-model AI collaboration
  # NOTE: Using 'final' because python3Packages may be modified by
  # pythonPackagesExtensions in other overlays
  pal-mcp-server =
    with final;
    with final.python3Packages;
    buildPythonApplication {
      pname = "pal-mcp-server";
      version = "9.8.2";
      pyproject = true;

      src = prev.inputs.pal-mcp-server;

      build-system = [
        setuptools
        setuptools-scm
      ];

      dependencies = [
        mcp
        google-genai
        openai
        pydantic
        python-dotenv
      ];

      env.SETUPTOOLS_SCM_PRETEND_VERSION = "9.8.2";

      doCheck = false;

      meta = {
        description = "AI-powered MCP server with multiple model providers";
        homepage = "https://github.com/BeehiveInnovations/pal-mcp-server";
        license = lib.licenses.mit;
        maintainers = with lib.maintainers; [ jwiegley ];
        mainProgram = "pal-mcp-server";
      };
    };

}
// {

  # Fix: npm prune removes @types/node, then prepare script tries to rebuild
  mcp-server-sequential-thinking = prev.mcp-server-sequential-thinking.overrideAttrs (old: {
    dontNpmPrune = true;
  });

  # Rust documentation MCP server
  rustdocs-mcp-server =
    with prev;
    rustPlatform.buildRustPackage rec {
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

  # Browser control MCP server
  browser-control-mcp =
    with prev;
    buildNpmPackage (finalAttrs: {
      pname = "browser-control-mcp";
      version = "1.5.1";

      src = fetchFromGitHub {
        owner = "eyalzh";
        repo = "browser-control-mcp";
        tag = "v${finalAttrs.version}";
        hash = "sha256-P0ZYjaHArngobtOf4C3j3LpuwfT4vZdJnoZnzeNoIWo=";
      };

      npmDepsHash = "sha256-NT0r3WHqg6ENVO4aPldUgs2doDJD+EEJcp78nNfbBnQ=";

      makeWrapperArgs = [ "--prefix PATH : ${lib.makeBinPath [ nodejs ]}" ];

      passthru.updateScript = nix-update-script { };

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

  # claude-replay - Convert Claude Code transcripts to HTML replays
  claude-replay =
    with prev;
    buildNpmPackage (finalAttrs: {
      pname = "claude-replay";
      version = "0.8.1";

      src = fetchFromGitHub {
        owner = "es617";
        repo = "claude-replay";
        tag = "v${finalAttrs.version}";
        hash = "sha256-RtXNyweM/VsmaDY1lKJCBs35Zzauskx7u8Y7vIeQExE=";
      };

      npmDepsHash = "sha256-/ugRMr+XXpTxKbqooFjDTR/dqZmZ/a1NBERLhBeOeCg=";

      makeWrapperArgs = [ "--prefix PATH : ${lib.makeBinPath [ nodejs ]}" ];

      meta = with lib; {
        description = "Convert Claude Code session transcripts into interactive, shareable HTML replays";
        homepage = "https://github.com/es617/claude-replay";
        license = licenses.mit;
        mainProgram = "claude-replay";
        maintainers = [ maintainers.jwiegley ];
        platforms = platforms.all;
      };
    });

  # Context Hub - AI agent documentation CLI and MCP server
  context-hub =
    with prev;
    buildNpmPackage (finalAttrs: {
      pname = "context-hub";
      version = "67dcbeb2";

      src = fetchFromGitHub {
        owner = "andrewyng";
        repo = "context-hub";
        rev = "67dcbeb2eb42c808549f08397920ad58be7c2206";
        hash = "sha256-iUibrCUVgO3U41x6NEchJRsST++PE92Hz3J0gbGt7p0=";
      };

      npmDepsHash = "sha256-AIjQTnfeXt8ROhHcS2vuYQ2HbXdI/MFa4/wnuQknjKA=";

      npmWorkspace = "cli";

      dontNpmBuild = true;

      npmFlags = [ "--ignore-scripts" ];

      # Remove dangling workspace symlinks left by npm workspace install
      postInstall = ''
        find $out -xtype l -delete
      '';

      makeWrapperArgs = [ "--prefix PATH : ${lib.makeBinPath [ nodejs ]}" ];

      meta = with lib; {
        description = "CLI and MCP server for Context Hub - search and retrieve LLM-optimized docs for AI agents";
        homepage = "https://github.com/andrewyng/context-hub";
        license = licenses.mit;
        mainProgram = "chub";
        maintainers = [ maintainers.jwiegley ];
        platforms = platforms.all;
      };
    });

  # drafts-mcp-server - MCP server that drives the Drafts app on macOS via
  # AppleScript (osascript). macOS-only by design (the upstream package.json
  # declares `"os": ["darwin"]`): it cannot run on Linux, so meta.platforms is
  # darwin and config/packages.nix installs it only under `isDarwin`. The
  # TypeScript source is compiled to dist/ by `tsc` (npm run build).
  drafts-mcp-server =
    with prev;
    buildNpmPackage (finalAttrs: {
      pname = "drafts-mcp-server";
      version = "1.0.12";

      src = fetchFromGitHub {
        owner = "agiletortoise";
        repo = "drafts-mcp-server";
        tag = "v${finalAttrs.version}";
        hash = "sha256-SZp//UKyFfwJyu7Cn5pG3Rp7P9l+4ElDZO7vYp78WzY=";
      };

      npmDepsHash = "sha256-nypoTffI8WIF9Et2GWLe/3odNJka9MSYuaP7xtLIoyg=";

      makeWrapperArgs = [ "--prefix PATH : ${lib.makeBinPath [ nodejs ]}" ];

      meta = with lib; {
        description = "MCP server that lets AI assistants drive the Drafts app on macOS via AppleScript";
        homepage = "https://github.com/agiletortoise/drafts-mcp-server";
        license = licenses.mit;
        mainProgram = "drafts-mcp-server";
        maintainers = [ maintainers.jwiegley ];
        platforms = platforms.darwin;
      };
    });

}
// prev.lib.optionalAttrs (prev ? inputs && prev.inputs ? stock-trader) {

  # stock-trader-mcp - REST-wrapper MCP server for the live stock-trader
  # service (8 core + 10 Alpha Vantage tools), the same tools OpenClaw uses.
  # A single script depending only on mcp + requests; the source lives in the
  # stock-trader repo (flake = false input). Bakes in the merged Vulcan CA
  # bundle (system roots + Vulcan's private root CA) so requests can verify
  # https://trader.vulcan.lan; both the CA bundle and base URL stay overridable
  # via the environment.
  stock-trader-mcp =
    let
      pyEnv = final.python3.withPackages (ps: [
        ps.mcp
        ps.requests
      ]);
      script = final.writeText "stock-trader-mcp.py" (
        builtins.readFile "${prev.inputs.stock-trader}/scripts/stock-trader-mcp.py"
      );
      caBundle =
        if prev ? ca-bundle-with-vulcan then
          "${prev.ca-bundle-with-vulcan}/etc/ssl/certs/ca-bundle.crt"
        else
          "${prev.cacert}/etc/ssl/certs/ca-bundle.crt";
    in
    final.writeShellApplication {
      name = "stock-trader-mcp";
      runtimeInputs = [ pyEnv ];
      text = ''
        export REQUESTS_CA_BUNDLE="''${REQUESTS_CA_BUNDLE:-${caBundle}}"
        export STOCK_TRADER_BASE_URL="''${STOCK_TRADER_BASE_URL:-https://trader.vulcan.lan}"
        exec python3 "${script}" "$@"
      '';
    };

}
